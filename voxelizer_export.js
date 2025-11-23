// At the end of voxelizer.worker.js, export voxelizeInNode for Node.js use
export async function voxelizeInNode(modelData, { resolution = 200, needGrid = false, method = '2.5d-scan' }) {
    return new Promise((resolve, reject) => {
        try {
            const result = voxelizeModelData(modelData, resolution, needGrid, method);
            resolve(result);
        } catch (error) {
            reject(error);
        }
    });
}
