local P,C,H=require('pattern'),require('pattern_circle_packing'),require('pattern_hash');local fs=require('lfs')
local checks=0;local rows=P.array();local function check(ok,why)assert(ok,why);checks=checks+1 end
for _,n in ipairs{6,24,60}do
 local faces={};for i=1,n do faces[#faces+1]={'center','b'..i,'b'..(i%n+1)}end
 local record=C.solve({faces=faces},{panel={.3,.3,5.7,5.7},tolerance=1e-11,iterations=600})
 check(C.validate(record),'Admitted fan falsely rejected:'..n)
 local expected=1/math.sin(math.pi/n)-1
 check(math.abs(record.circles.center.radius/record.circles.b1.radius-expected)<1e-10,'Analytical central/boundary radius ratio')
 local bad=P.plain(record);bad.maximum_angular_residual=bad.maximum_angular_residual+1e-7
 check(not pcall(C.validate,bad),'Bad residual receipt accepted')
 bad=P.plain(record);bad.circles.center.radius=bad.circles.center.radius*1.001
 check(not pcall(C.validate,bad),'Bad circle radius accepted')
 bad=P.plain(record);bad.circles.b1.center[1]=bad.circles.b1.center[1]+1e-6
 check(not pcall(C.validate,bad),'Bad recorded position accepted')
 rows[#rows+1]={spokes=n,packing=record,analytic_radius_ratio=expected}
end
local source={};for _,name in ipairs{'pattern_circle_packing.lua','tools/check-packing-scale.lua'}do local f=assert(io.open(name,'rb'));source[name]=H.sha256(f:read('*a'));f:close()end
fs.mkdir('build');fs.mkdir('build/packing-scale');local result={status='passed',checks=checks,actual_lua=_VERSION,source_files=source,source_digest=H.value('packing-scale/test-source',source),unchanged_angular_tolerance=1e-11,unchanged_receipt_bound=1e-14,cases=rows}
local f=assert(io.open('build/packing-scale/receipt-'.._VERSION:gsub(' ','-')..'.json','wb'));f:write(P.serialize(result));f:close();print('Circle packing scale/corruption checks',checks,_VERSION);return result
