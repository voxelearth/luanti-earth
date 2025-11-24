#ifndef DEBUG_LOG_H
#define DEBUG_LOG_H

#include <fstream>
#include <string>
#include <iostream>

inline void log_debug(const std::string& msg) {
    // Write to a hardcoded path to ensure we find it
    // Using C:/Users/Public/ for write permissions usually, or just C:/tmp if it exists.
    // Let's try the current working directory first, but also print to cerr.
    
    std::ofstream logfile("C:/Users/cortanium/luanti_native_debug.txt", std::ios::app);
    if (logfile.is_open()) {
        logfile << msg << std::endl;
        logfile.close();
    }
    // Also try cerr
    std::cerr << msg << std::endl;
}

#endif
