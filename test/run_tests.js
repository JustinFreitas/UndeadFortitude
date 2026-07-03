const { LuaFactory } = require('wasmoon');
const fs = require('fs');
const path = require('path');

async function run() {
  const factory = new LuaFactory();
  const lua = await factory.createEngine();

  // Load all parts
  const mocksPath = path.join(__dirname, 'mocks.lua');
  const scriptPath = path.join(__dirname, '../scripts/undeadfortitude.lua');
  const testsPath = path.join(__dirname, 'tests.lua');

  const mocksContent = fs.readFileSync(mocksPath, 'utf8');
  const scriptContent = fs.readFileSync(scriptPath, 'utf8');
  const testsContent = fs.readFileSync(testsPath, 'utf8');

  // Run them in order
  console.log('Loading Mocks...');
  await lua.doString(mocksContent);

  console.log('Loading undeadfortitude.lua...');
  await lua.doString(scriptContent);

  console.log('Running Tests...');
  await lua.doString(testsContent);

  // Retrieve global test counters
  const passed = lua.global.get('passed');
  const failed = lua.global.get('failed');

  console.log(`\nTest counters retrieved: passed=${passed}, failed=${failed}`);

  if (failed > 0) {
    console.error(`\nSome tests failed. Passed: ${passed}, Failed: ${failed}`);
    process.exit(1);
  } else {
    console.log(`\nAll ${passed} tests passed successfully.`);
    process.exit(0);
  }
}

run().catch(err => {
  console.error('Error running test suite:', err);
  process.exit(1);
});
