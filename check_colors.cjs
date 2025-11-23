const fs = require('fs');
const path = process.argv[2];
if (!path) {
    console.error('Usage: node check_colors.cjs <voxel_json_path>');
    process.exit(1);
}
const data = JSON.parse(fs.readFileSync(path, 'utf8'));
const colors = new Set();
for (const v of data.voxels) {
    colors.add(`${v.r},${v.g},${v.b}`);
}
console.log('Distinct colors:', colors.size);
console.log('Sample colors:', [...colors].slice(0, 20).join(' | '));
