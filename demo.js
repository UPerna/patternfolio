import { PatternWorkerClient } from './studio/client.js';

const get = id => document.getElementById(id);
const client = new PatternWorkerClient('./studio/');
const pattern = get('pattern');
const phase = get('phase');
const seed = get('seed');
const generate = get('generate');
const copy = get('copy');
const recipeLink = get('recipe');
const svgLink = get('svg');
const status = get('status');
const decoder = new TextDecoder('utf-8', { fatal: true });
let recipes;
let result;
let resultUrls = [];

function refreshFields() {
  const isPenrose = pattern.value === 'penrose';
  get('phase-field').hidden = !isPenrose;
  get('seed-field').hidden = isPenrose;
  seed.disabled = isPenrose;
}

function showResult(svg, recipe) {
  const svgUrl = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml' }));
  const recipeUrl = URL.createObjectURL(new Blob([recipe], { type: 'application/json' }));
  const previousUrls = resultUrls;
  resultUrls = [svgUrl, recipeUrl];
  result = recipe;
  get('art').src = svgUrl;
  get('art').alt = 'Generated ' + pattern.selectedOptions[0].textContent.toLowerCase();
  get('caption').textContent = pattern.selectedOptions[0].textContent;
  svgLink.href = svgUrl;
  svgLink.download = pattern.value + '.svg';
  recipeLink.href = recipeUrl;
  recipeLink.hidden = false;
  for (const url of previousUrls) URL.revokeObjectURL(url);
}

pattern.addEventListener('change', refreshFields);
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
  generate.disabled = pattern.disabled = phase.disabled = seed.disabled = copy.disabled = true;
  status.textContent = 'Generating pattern…';
  try {
    const output = await client.execute({
      command: 'generate',
      files: { 'recipe.json': JSON.stringify(recipe) },
      formats: ['svg'],
    });
    const record = JSON.parse(decoder.decode(output.assets['record.json']));
    if (record.status !== 'complete' || !output.assets['pattern.svg']) {
      throw new Error('The generator did not return a complete SVG.');
    }
    showResult(output.assets['pattern.svg'], decoder.decode(output.assets['recipe.json']));
    status.textContent = 'Pattern ready. Download the SVG or keep its recipe.';
  } catch (error) {
    status.textContent = 'Generation failed. ' + error.message;
  } finally {
    generate.disabled = pattern.disabled = phase.disabled = false;
    copy.disabled = !result;
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

try {
  const { bundle } = await client.load();
  const catalog = JSON.parse(bundle.examples['catalog.json']).examples;
  recipes = new Map([...pattern.options].map(option => {
    const row = catalog.find(entry => entry.id === option.value);
    return [option.value, bundle.examples[row.recipe]];
  }));
  seed.value = JSON.parse(recipes.get('botanical-panel')).design.seed;
  generate.disabled = false;
  status.textContent = 'Choose a pattern and select Generate pattern.';
} catch {
  status.textContent = 'The engine could not load. Reload to try again, or download the Compass Garden SVG.';
}
