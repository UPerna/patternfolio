-- Engine-neutral document adapter: cached semantic instances and physical views.
local P,Q,R,H,V,G,D=require('pattern'),require('pattern_recipe'),require('pattern_registry'),
  require('pattern_hash'),require('pattern_render'),require('pattern_geometry'),require('pattern_document')
local Random=require('pattern_random')
local M={VERSION='pattern-tex-v1'}
local function need(ok,why)assert(ok,'pattern-tex: '..why)end
local function finite(n)return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function box(b)
  need(type(b)=='table' and #b==4,'four physical bounds required')
  for _,n in ipairs(b)do need(finite(n),'nonfinite physical bounds')end
  need(b[3]>b[1] and b[4]>b[2],'selected region has no positive area');return b
end
local function intersection(a,b)
  local c={math.max(a[1],b[1]),math.max(a[2],b[2]),math.min(a[3],b[3]),math.min(a[4],b[4])}
  if c[1]<c[3] and c[2]<c[4]then return c end
end
local function mapped(b,m)return {b[1]*m[1]+m[5],b[2]*m[4]+m[6],b[3]*m[1]+m[5],b[4]*m[4]+m[6]}end
local function print_requirements(asset)
  local options=asset.recipe.view.extensions and asset.recipe.view.extensions.document_planning.options or {}
  return {minimum_stroke=options.minimum_stroke,minimum_text_size=options.minimum_text_size}
end
local function expanded(b,p)return {b[1]-p,b[2]-p,b[3]+p,b[4]+p}end
local function available(crop,masks)
  local pieces={crop}
  for _,mask in ipairs(masks)do
    local nexts={}
    for _,b in ipairs(pieces)do
      local hit=intersection(b,mask.bounds)
      if not hit then nexts[#nexts+1]=b else
        for _,r in ipairs({{b[1],b[2],hit[1],b[4]},{hit[3],b[2],b[3],b[4]},
            {hit[1],b[2],hit[3],hit[2]},{hit[1],hit[4],hit[3],b[4]}})do
          if r[1]<r[3] and r[2]<r[4]then nexts[#nexts+1]=r end
        end
      end
    end
    need(#nexts<=4096,'reservation partition budget exceeded');pieces=nexts
  end
  local area=0;for _,b in ipairs(pieces)do area=area+(b[3]-b[1])*(b[4]-b[2])end
  need(area>1e-12,'selected pattern view is fully protected; choose another region or explicitly disable text protection')
  return area
end
local function page_data(page,id,origin,masks)
  local w,h=page.size[1],page.size[2];local b=box(page.content)
  need(b[1]>=0 and b[2]>=0 and b[3]<=w and b[4]<=h,'actual text rectangle leaves the physical media')
  local reservations=P.array()
  for i,r in ipairs(masks)do reservations[i]={id='mask/'..i,bounds=P.plain(r.bounds),space='page',role='protected_content'}end
  return {id=id,number=page.index,size={w,h},origin=origin,margins={b[1],b[2],w-b[3],h-b[4]},
    protected_regions=reservations,anchors=P.plain(page.anchors or P.array())}
end
function M.new(host)
  need(type(host)=='table' and type(host.source)=='table' and type(host.runtime)=='string','trusted source bytes/runtime required')
  local source_hashes={};for name,bytes in pairs(host.source)do source_hashes[name]=H.sha256(bytes)end
  local source={revision='source/'..H.value('tex/source',source_hashes),
    files={construction=host.source,style={},view={},renderer={}}}
  local self={assets={},generated={},generations=0,views=0,source_hashes=source_hashes}
  function self:declare(name,bytes,inputs)
    need(type(name)=='string' and name:match('^[A-Za-z][A-Za-z0-9_-]*$') and #name<=64,'asset name must use letters, digits, underscore or hyphen')
    need(not self.assets[name],'asset already declared: '..name)
    local q=Q.decode(bytes);local canonical=Q.encode(q)
    local environment=Q.environment(source,{lua=_VERSION,host=host.runtime},{id=V.VERSION,version='1'},inputs or {})
    local key=H.value('tex/generation',{recipe=H.sha256(canonical),source=environment.source.digest,
      runtime=P.plain(environment.runtime),renderer=P.plain(environment.renderer),inputs=P.plain(environment.inputs)})
    local a=self.generated[key]
    if not a then
      local registry,d=require('pattern_cli_core').registry(q.definition.id)
      local result=Q.execute(q,registry,environment)
      need(result.record.status=='complete',table.concat(P.plain(result.record.diagnostics),'; '))
      a={recipe=q,definition=d,registry=registry,result=result,environment=environment,inputs=inputs or {},key=key,
        recipe_bytes=canonical,instance_sha256=H.sha256(result.bytes.instance)}
      self.generated[key]=a;self.generations=self.generations+1
    end
    self.assets[name]=a;return a
  end
  function self:asset(name)
    local asset=self.assets[name];need(asset,'unknown asset '..tostring(name));return asset
  end
  function self:plan(name)
    local a=self:asset(name)
    return V.plan(a.result.scene,a.result.instance,a.result.view,a.definition),a
  end
  function self:inline(name,width)
    need(finite(width) and width>=0,'inline width must be finite and nonnegative')
    local plan,asset=self:plan(name)
    local natural=plan.bounds[3]-plan.bounds[1]
    local scale=width>0 and width/natural or 1
    local requirements=print_requirements(asset)
    -- Compare in source units using the existing affine rounding guard. Positive
    -- uniform inclusion scales both physical minima and their error bounds.
    local source_units={}
    for key,value in pairs(requirements)do source_units[key]=value/scale end
    local valid,report=pcall(require('pattern_planner').check_render_requirements,plan,source_units)
    need(valid,type(report)=='table' and report.message or tostring(report))
    report=P.plain(report)
    for key,value in pairs(report)do if type(value)=='number'then report[key]=value*scale end end
    return plan,asset,{width=natural*scale,height=(plan.bounds[4]-plan.bounds[2])*scale,
      scale=scale,print_requirements=report}
  end
  function self:place(name,page,options)
    local a=self:asset(name);options=P.plain(options or {})
    local known={region=true,spread=true,protect_text=true,padding=true}
    for k in pairs(options)do need(known[k],'unknown view option '..tostring(k))end
    local region=options.region or 'outer';local spread=options.spread or 'none'
    need(spread=='none' or spread=='left' or spread=='right','unsupported spread side')
    local protect=options.protect_text;if protect==nil then protect=true end
    need(type(protect)=='boolean','protect_text must be boolean')
    local pad=options.padding or .3;need(finite(pad) and pad>=0 and pad<=2,'padding must be 0..2 cm')
    need(finite(page.index) and page.index>=1 and page.index%1==0,'actual positive shipped-page index required')
    local w,h=page.size[1],page.size[2];box({0,0,w,h});local body=box(page.content)
    local right=not page.twoside or page.logical_number%2==1
    local slots={page={pad,pad,w-pad,h-pad},content=body,
      left={pad,body[2],body[1]-pad,body[4]},right={body[3]+pad,body[2],w-pad,body[4]},
      header={body[1],page.header_top+pad,body[3],h-pad},
      footer={body[1],pad,body[3],page.footer_bottom-pad}}
    slots.outer=right and slots.right or slots.left;slots.inner=right and slots.left or slots.right
    need(region=='page' or region=='content' or region=='outer' or region=='inner' or region=='header' or region=='footer','unsupported region '..tostring(region))
    local slot=box(slots[region]);local b=a.recipe.view.crop
    if spread~='none'then
      need(region=='page' and pad==0,'spread requires region=page and padding=0')
      slot={0,0,2*w,h}
      if spread=='left'then
        need(page.index%2==0 and not self.spread,'left spread must begin on an actual even shipped page with no open pair')
      else
        need(self.spread and self.spread.name==name and page.index==self.spread.index+1,'right spread must immediately follow its declared left page')
        need(self.spread.width==w and self.spread.height==h and self.spread.asset==a.key,'spread media/instance changed')
      end
    end
    local scale=math.min((slot[3]-slot[1])/(b[3]-b[1]),(slot[4]-slot[2])/(b[4]-b[2]))
    local fit={scale,0,0,scale,(slot[1]+slot[3]-scale*(b[1]+b[3]))/2,
      (slot[2]+slot[4]-scale*(b[2]+b[4]))/2}
    if spread=='right'then fit[5]=fit[5]-w end
    local crop=intersection(mapped(b,fit),{0,0,w,h});need(crop,'source recipe view does not reach this page')
    local masks=P.array()
    local function reserve(r)box(r);masks[#masks+1]={bounds=P.plain(r),role='protected_content'}end
    if protect then
      reserve(expanded(body,pad))
      for _,r in ipairs(page.running_regions or {})do reserve(expanded(r,pad))end
    end
    for _,r in ipairs(page.reservations or {})do reserve(r)end
    for _,r in ipairs(a.recipe.view.protected_regions)do reserve(mapped(r.bounds,fit))end
    local visible_area=available(crop,masks)
    local document=D.new({id='tex/page/'..page.index,unit='cm',frame={id='tex/physical-document',origin={0,0}},twoside=not not page.twoside,
      pages={page_data(page,'page/'..page.index,{0,0},masks)},spreads=P.array()})
    local requirements=print_requirements(a)
    local settings={id=a.result.instance.id..'/tex/'..H.value('tex/view',{transform=fit,crop=crop,masks=masks,
        source_view=H.sha256(P.serialize(a.recipe.view)),
        document=H.sha256(P.serialize(document)),label=page.label,logical_number=page.logical_number}),
      instance_ref=a.result.instance.id,unit='cm',transform=G.compose(fit,a.recipe.view.transform),crop=crop,
      protected_regions=masks,derived=a.recipe.view.derived,validity=a.recipe.view.validity,
      projection=a.recipe.view.projection and P.plain(a.recipe.view.projection) or nil,
      extensions={tex_document={schema_version=1,document=P.plain(document),physical_index=page.index,
        logical_number=page.logical_number,printed_label=page.label,geometry=P.plain(page),spread=spread,
        source_recipe_view=H.sha256(P.serialize(a.recipe.view)),available_crop_area=visible_area,
        print_requirements=P.plain(requirements)}}}
    local view=P.view(settings,a.result.instance,a.definition)
    local context=R.context({seed=a.recipe.design.seed,source=a.environment.source,versions={lua=_VERSION,host=host.runtime},
      frame=P.plain(a.result.instance.frame),limits=a.recipe.design.budget,
      stream_provider=Random.provider(a.recipe.design.seed,a.definition.id..'@'..a.definition.version),
      input_provider=function(key)return assert(a.inputs[key],'missing declared dependency')end})
    -- Retain the original planner's selection and internal clips. Re-running a
    -- bare family lower here could reveal tiles excluded by a full-tile view.
    local data=P.plain(a.result.scene)
    data.id=view.id..'/scene';data.view_ref=view.id
    data.clip={bounds=P.plain(crop),protected_regions=P.plain(masks)}
    for _,operation in ipairs(data.operations)do
      if operation.op~='pop_clip'then
        operation.transform=G.compose(fit,operation.transform or {1,0,0,1,0,0})
      end
    end
    local scene=P.scene(data,a.result.instance,view,a.definition)
    context:consume('operations',#scene.operations);context:consume('bytes',#P.serialize(scene))
    local plan=V.plan(scene,a.result.instance,view,a.definition)
    local valid,print_report=pcall(require('pattern_planner').check_render_requirements,plan,requirements)
    need(valid,type(print_report)=='table' and print_report.message or tostring(print_report))
    local vb,sb=P.serialize(view),P.serialize(scene);local pdf=V.pdf(plan)
    local record={status='complete',source=P.plain(a.environment.source),runtime={name=_VERSION,version=host.runtime},
      seed=a.recipe.design.seed,inputs={{kind='recipe',sha256=H.sha256(a.recipe_bytes)},
        {kind='validated_source_scene',sha256=H.sha256(a.result.bytes.scene)},
        {kind='stored_instance',sha256=a.instance_sha256},{kind='physical_document',sha256=H.sha256(P.serialize(document))}},
      dependencies={renderer=V.VERSION,source_recipe_view=H.sha256(P.serialize(a.recipe.view))},
      lineage={{role='physical-document-view',parent_ref=a.result.record.id,instance_sha256=a.instance_sha256}},
      validation={status='passed',print_requirements=P.plain(print_report),checks={'Previously generated and structurally validated semantic instance',
        'Typed physical document, source-preserving positive uniform view, scene and protected clips',
        'Source-declared physical print minima checked after fitting','No generator invocation at shipout'}},
      outputs={{kind='view',sha256=H.sha256(vb)},{kind='scene',sha256=H.sha256(sb)},{kind='pdf',sha256=H.sha256(pdf)}},
      diagnostics=P.array(),budgets=context:receipt()}
    record.id='build/'..H.value('tex/view-record',record);record=P.build_record(record)
    self.views=self.views+1
    local spread_document
    if spread=='left'then self.spread={name=name,index=page.index,width=w,height=h,asset=a.key,page=P.plain(page),masks=P.plain(masks)}
    elseif spread=='right'then
      local left=self.spread
      spread_document=D.new({id='tex/spread/'..left.index,unit='cm',frame={id='tex/physical-document',origin={0,0}},twoside=true,
        pages={page_data(left.page,'left',{0,0},left.masks),page_data(page,'right',{w,0},masks)},
        spreads={{id='pair',left='left',right='right',gutter=0}}})
      self.spread=nil
    end
    return {view=view,scene=scene,plan=plan,pdf=pdf,record=record,asset=a,
      spread_document=spread_document,key=H.value('tex/output',{source=a.environment.source.digest,record=record.id}),
      bytes={view=vb,scene=sb,record=P.serialize(record)},crop=crop}
  end
  function self:finish()need(not self.spread,'spread left page has no matching right page')end
  return self
end
return M
