import { PatternWorkerClient } from './studio/client.js';

const get = id => document.getElementById(id);
const client = new PatternWorkerClient('./studio/');
const pattern = get('pattern');
const phase = get('phase');
const seed = get('seed');
const generate = get('generate');
const copy = get('copy');
const share = get('share');
const cancel = get('cancel');
const recipeLink = get('recipe');
const svgLink = get('svg');
const pdfLink = get('pdf');
const status = get('status');
const decoder = new TextDecoder('utf-8', { fatal: true });
let recipes;
let result;
let resultLink;
let resultUrls = [];

function refreshFields() {
  const isPenrose = pattern.value === 'penrose';
  get('phase-field').hidden = !isPenrose;
  get('seed-field').hidden = isPenrose;
  seed.disabled = isPenrose;
}

function showResult(svg, pdf, recipe) {
  const svgUrl = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml' }));
  const pdfUrl = URL.createObjectURL(new Blob([pdf], { type: 'application/pdf' }));
  const recipeUrl = URL.createObjectURL(new Blob([recipe], { type: 'application/json' }));
  const previousUrls = resultUrls;
  resultUrls = [svgUrl, pdfUrl, recipeUrl];
  result = recipe;
  const accepted = JSON.parse(recipe);
  const url = new URL(location.pathname, location.origin);
  url.searchParams.set('pattern', pattern.value);
  if (pattern.value === 'penrose') {
    url.searchParams.set('phase', accepted.design.parameters.phase);
  } else {
    url.searchParams.set('seed', accepted.design.seed);
  }
  resultLink = url.href;
  get('share-fallback').hidden = true;
  get('art').src = svgUrl;
  get('art').alt = 'Generated ' + pattern.selectedOptions[0].textContent.toLowerCase();
  get('caption').textContent = pattern.selectedOptions[0].textContent;
  svgLink.href = svgUrl;
  svgLink.download = pattern.value + '.svg';
  pdfLink.href = pdfUrl;
  pdfLink.download = pattern.value + '.pdf';
  pdfLink.textContent = 'Download PDF';
  recipeLink.href = recipeUrl;
  recipeLink.download = pattern.value + '.recipe';
  recipeLink.hidden = false;
  for (const url of previousUrls) URL.revokeObjectURL(url);
}

function noteChange() {
  refreshFields();
  if (result) status.textContent = 'Settings changed. Generate to update the preview and downloads.';
}

pattern.addEventListener('change', noteChange);
phase.addEventListener('change', noteChange);
seed.addEventListener('input', noteChange);
cancel.addEventListener('click', () => client.cancel());
refreshFields();

get('controls').addEventListener('submit', async event => {
  event.preventDefault();
  if (!recipes || generate.disabled) return;
  const recipe = JSON.parse(recipes.get(pattern.value));
  if (pattern.value === 'penrose') {
    recipe.design.parameters.phase = phase.value;
  } else {
    const value = seed.valueAsNumber;
    if (!Number.isSafeInteger(value)) {
      status.textContent = 'Enter a whole-number seed.';
      return;
    }
    recipe.design.seed = value;
  }
  generate.disabled = pattern.disabled = phase.disabled = seed.disabled = copy.disabled = share.disabled = true;
  cancel.hidden = false;
  status.textContent = 'Generating pattern…';
  try {
    const output = await client.execute({
      command: 'generate',
      files: { 'recipe.json': JSON.stringify(recipe) },
      formats: ['svg', 'pdf'],
    });
    const record = JSON.parse(decoder.decode(output.assets['record.json']));
    const svg = output.assets['pattern.svg'];
    const pdf = output.assets['pattern.pdf'];
    if (record.status !== 'complete' || !svg || !pdf) {
      throw new Error('The generator did not return a complete SVG and PDF.');
    }
    showResult(svg, pdf, decoder.decode(output.assets['recipe.json']));
    status.textContent = 'Pattern ready. Download the SVG, PDF or recipe.';
  } catch (error) {
    status.textContent = error.code === 'cancelled'
      ? 'Generation cancelled. The previous preview and downloads are still available.'
      : 'Generation failed. ' + error.message;
  } finally {
    generate.disabled = pattern.disabled = phase.disabled = false;
    cancel.hidden = true;
    copy.disabled = share.disabled = !result;
    refreshFields();
  }
});

copy.addEventListener('click', async () => {
  if (!result) return;
  try {
    await navigator.clipboard.writeText(result);
    status.textContent = 'Recipe copied.';
  } catch {
    status.textContent = 'Clipboard unavailable. Use Download recipe.';
  }
});

share.addEventListener('click', async () => {
  if (!resultLink) return;
  try {
    await navigator.clipboard.writeText(resultLink);
    status.textContent = 'Pattern link copied.';
  } catch {
    const fallback = get('share-fallback');
    fallback.value = resultLink;
    fallback.hidden = false;
    fallback.select();
    status.textContent = 'Copy the pattern link from the selected field.';
  }
});

try {
  const { bundle } = await client.load();
  const catalog = JSON.parse(bundle.examples['catalog.json']).examples;
  recipes = new Map([...pattern.options].map(option => {
    const row = catalog.find(entry => entry.id === option.value);
    return [option.value, bundle.examples[row.recipe]];
  }));
  seed.value = JSON.parse(recipes.get('botanical-panel')).design.seed;
  generate.disabled = pattern.disabled = phase.disabled = false;
  const params = new URLSearchParams(location.search);
  const requested = params.get('pattern');
  if (recipes.has(requested)) {
    pattern.value = requested;
    const requestedPhase = params.get('phase');
    if (requested === 'penrose' && ['amber', 'indigo'].includes(requestedPhase)) {
      phase.value = requestedPhase;
    }
    const requestedSeed = params.get('seed');
    if (requested === 'botanical-panel' && /^-?\d+$/.test(requestedSeed ?? '') &&
        Number.isSafeInteger(Number(requestedSeed))) {
      seed.value = requestedSeed;
    }
    refreshFields();
    get('controls').requestSubmit();
  } else {
    status.textContent = 'Choose a pattern and select Generate pattern.';
  }
} catch {
  status.textContent = 'The engine could not load. Reload to try again, or download the Compass Garden SVG.';
}
