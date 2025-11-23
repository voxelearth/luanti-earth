import fs from 'fs';
import path from 'path';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import * as THREE from 'three';
import { voxelizeInNode } from './voxelizer.worker.js';
import jpeg from 'jpeg-js';

const args = process.argv.slice(2);
if (args.length < 2) {
    console.error('Usage: node voxelize_tiles.js <input_dir> <output_dir> [resolution]');
    process.exit(1);
}

const inputDir = args[0];
const outputDir = args[1];
const resolution = parseInt(args[2]) || 200;

if (!fs.existsSync(inputDir)) {
    console.error(`Input directory does not exist: ${inputDir}`);
    process.exit(1);
}

if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
}

const loader = new GLTFLoader();

async function serializeModel(model, gltf) {
    const meshes = [];
    const materialStore = new Map();
    const imageDatas = [];

    model.updateWorldMatrix(true, true);

    // Extract images
    if (gltf && gltf.parser && gltf.parser.json && gltf.parser.json.images) {
        const images = gltf.parser.json.images;
        for (let i = 0; i < images.length; i++) {
            try {
                const imageDef = images[i];
                if (imageDef.bufferView !== undefined) {
                    const bufferView = await gltf.parser.getDependency('bufferView', imageDef.bufferView);
                    const decoded = jpeg.decode(bufferView, { useTArray: true });
                    imageDatas.push([i.toString(), {
                        data: Array.from(decoded.data),
                        width: decoded.width,
                        height: decoded.height
                    }]);
                    console.log(`  Decoded image ${i}: ${decoded.width}x${decoded.height}`);
                }
            } catch (err) {
                console.warn(`  Failed to load image ${i}:`, err.message);
            }
        }
    }

    // Calculate bbox and center
    const bbox = new THREE.Box3().setFromObject(model);
    const center = new THREE.Vector3();
    bbox.getCenter(center);
    console.log(`  Center: [${center.toArray().map(v => v.toFixed(1)).join(', ')}]`);

    model.traverse(o => {
        if (!o.isMesh || !o.geometry || !o.geometry.isBufferGeometry) return;

        const mats = Array.isArray(o.material) ? o.material : [o.material];
        for (const mat of mats) {
            if (!mat || materialStore.has(mat.uuid)) continue;

            const m = {
                uuid: mat.uuid,
                type: mat.type,
                color: mat.color ? mat.color.getHex() : undefined,
                emissive: mat.emissive ? mat.emissive.getHex() : undefined,
            };

            if (mat.map && gltf.parser.json) {
                const materials = gltf.parser.json.materials || [];
                const textures = gltf.parser.json.textures || [];
                for (let i = 0; i < materials.length; i++) {
                    if (materials[i].pbrMetallicRoughness?.baseColorTexture) {
                        const texIdx = materials[i].pbrMetallicRoughness.baseColorTexture.index;
                        const imageIdx = textures[texIdx]?.source;
                        if (imageIdx !== undefined) {
                            m.map = imageIdx.toString();
                            break;
                        }
                    }
                }
            }

            materialStore.set(mat.uuid, m);
        }

        const g = o.geometry;
        const attributes = {};

        for (const [name, attr] of Object.entries(g.attributes)) {
            const clone = new (attr.array.constructor)(attr.array);

            if (name === 'position' && attr.itemSize === 3) {
                for (let i = 0; i < clone.length; i += 3) {
                    clone[i + 0] -= center.x;
                    clone[i + 1] -= center.y;
                    clone[i + 2] -= center.z;
                }
            }

            attributes[name] = { array: clone, itemSize: attr.itemSize };
        }

        meshes.push({
            geometry: {
                attributes,
                groups: g.groups,
                index: g.index ? { array: new (g.index.array.constructor)(g.index.array) } : null
            },
            materials: mats.map(m => m.uuid),
            matrixWorld: o.matrixWorld.toArray()
        });
    });

    const centeredBBox = new THREE.Box3(
        new THREE.Vector3(bbox.min.x - center.x, bbox.min.y - center.y, bbox.min.z - center.z),
        new THREE.Vector3(bbox.max.x - center.x, bbox.max.y - center.y, bbox.max.z - center.z)
    );

    return {
        meshes,
        materials: Array.from(materialStore.values()),
        imageDatas,
        bbox: { min: centeredBBox.min.toArray(), max: centeredBBox.max.toArray() },
        worldOffset: center.toArray()
    };
}

async function loadGLB(filePath) {
    return new Promise((resolve, reject) => {
        const buffer = fs.readFileSync(filePath);
        const arrayBuffer = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
        loader.parse(arrayBuffer, path.dirname(filePath), (gltf) => resolve({ scene: gltf.scene, gltf }), reject);
    });
}

async function voxelizeGLB(glbPath, outputPath) {
    const baseName = path.basename(glbPath, '.glb');
    const jsonPath = path.join(outputPath, `${baseName}_voxels.json`);

    if (fs.existsSync(jsonPath)) {
        console.log(`[SKIP] ${baseName}`);
        return;
    }

    console.log(`[PROCESSING] ${baseName}...`);

    try {
        const { scene, gltf } = await loadGLB(glbPath);
        const modelData = await serializeModel(scene, gltf);

        const result = await voxelizeInNode(modelData, { resolution, needGrid: true, method: '2.5d-scan' });

        console.log(`  Voxelization: count=${result?.voxelCount || 0}`);

        if (!result || !result.voxelGrid) {
            console.warn(`[WARN] No voxelGrid`);
            return;
        }

        const { voxelCounts, voxelColors, gridSize, bbox, unit } = result.voxelGrid;

        if (!voxelCounts) {
            console.warn(`[WARN] No voxelCounts`);
            return;
        }

        const NX = gridSize.x, NY = gridSize.y, NZ = gridSize.z;
        const worldOffset = modelData.worldOffset;
        const voxels = [];

        for (let z = 0; z < NZ; z++) {
            for (let y = 0; y < NY; y++) {
                for (let x = 0; x < NX; x++) {
                    const idx = x + NX * (y + NY * z);
                    if (voxelCounts[idx] > 0) {
                        const r = Math.floor((voxelColors[idx * 4 + 0] || 0) * 255);
                        const g = Math.floor((voxelColors[idx * 4 + 1] || 0) * 255);
                        const b = Math.floor((voxelColors[idx * 4 + 2] || 0) * 255);
                        const a = Math.floor((voxelColors[idx * 4 + 3] || 1) * 255);
                        const wx = bbox.min[0] + (x + 0.5) * unit.x + worldOffset[0];
                        const wy = bbox.min[1] + (y + 0.5) * unit.y + worldOffset[1];
                        const wz = bbox.min[2] + (z + 0.5) * unit.z + worldOffset[2];
                        voxels.push({ x, y, z, wx, wy, wz, r, g, b, a });
                    }
                }
            }
        }

        const output = {
            file: baseName,
            resolution,
            gridSize: { x: NX, y: NY, z: NZ },
            bbox: { min: { x: bbox.min[0], y: bbox.min[1], z: bbox.min[2] }, max: { x: bbox.max[0], y: bbox.max[1], z: bbox.max[2] } },
            worldOffset: { x: worldOffset[0], y: worldOffset[1], z: worldOffset[2] },
            unit: { x: unit.x, y: unit.y, z: unit.z },
            voxelCount: voxels.length,
            voxels
        };

        fs.writeFileSync(jsonPath, JSON.stringify(output, null, 2));
        console.log(`[SUCCESS] ${voxels.length} voxels`);

    } catch (error) {
        console.error(`[ERROR] ${baseName}:`, error.message);
    }
}

async function main() {
    const files = fs.readdirSync(inputDir)
        .filter(f => f.endsWith('.glb') && !f.endsWith('_downloaded.glb'))
        .map(f => path.join(inputDir, f));

    console.log(`Found ${files.length} GLB files`);

    for (const file of files) {
        await voxelizeGLB(file, outputDir);
    }

    console.log('Complete!');
}

main().catch(err => { console.error('Fatal:', err); process.exit(1); });
