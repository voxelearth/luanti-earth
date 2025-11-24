#pragma once
#include <string>
#include <vector>
#include <functional>

struct TileData {
    std::string url;
    std::vector<unsigned char> data;
    // Add metadata like translation, etc.
};

class TileDownloader {
public:
    TileDownloader(const std::string& apiKey);
    
    // Downloads tiles intersecting the region
    std::vector<TileData> downloadTiles(double lat, double lon, double radius);
    
    std::vector<unsigned char> fetchUrlPublic(const std::string& url);

private:
    std::string apiKey;
    
    // Helper to fetch a URL, returns (data, content-type)
    std::pair<std::vector<unsigned char>, std::string> fetchUrl(const std::string& url);
};
