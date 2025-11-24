#pragma once
#include <vector>
#include <string>

struct Voxel {
    int x, y, z;
    unsigned char r, g, b, a;
};

struct VoxelGrid {
    std::vector<Voxel> voxels;
    // Add bounds, scale, etc.
};

class Voxelizer {
public:
    VoxelGrid voxelize(const std::vector<unsigned char>& glbData, int resolution, double originX, double originY, double originZ);
};
