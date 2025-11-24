extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}
#include <iostream>
#include "downloader.h"
#include "voxelizer.h"



static int l_download_and_voxelize(lua_State* L) {
    // Arguments: lat, lon, radius, resolution, api_key
    double lat = luaL_checknumber(L, 1);
    double lon = luaL_checknumber(L, 2);
    double radius = luaL_checknumber(L, 3);
    int resolution = luaL_checkinteger(L, 4);
    const char* api_key = luaL_checkstring(L, 5);



    TileDownloader downloader(api_key);
    auto tiles = downloader.downloadTiles(lat, lon, radius);

    Voxelizer voxelizer;
    lua_newtable(L); // Result table
    int idx = 1;

    for (const auto& tile : tiles) {
        VoxelGrid grid = voxelizer.voxelize(tile.data, resolution);
        
        // Append to result table
        for (const auto& v : grid.voxels) {
            lua_newtable(L);
            lua_pushinteger(L, v.x); lua_setfield(L, -2, "x");
            lua_pushinteger(L, v.y); lua_setfield(L, -2, "y");
            lua_pushinteger(L, v.z); lua_setfield(L, -2, "z");
            lua_pushinteger(L, v.r); lua_setfield(L, -2, "r");
            lua_pushinteger(L, v.g); lua_setfield(L, -2, "g");
            lua_pushinteger(L, v.b); lua_setfield(L, -2, "b");
            lua_pushinteger(L, v.a); lua_setfield(L, -2, "a");
            
            lua_rawseti(L, -2, idx++);
        }
    }

    return 1;
}

static const struct luaL_Reg earth_native_lib[] = {
    {"download_and_voxelize", l_download_and_voxelize},
    {NULL, NULL}
};

extern "C" {
#ifdef _WIN32
    __declspec(dllexport)
#endif
    int luaopen_earth_native(lua_State* L) {
        luaL_register(L, "earth_native", earth_native_lib);
        return 1;
    }
}
