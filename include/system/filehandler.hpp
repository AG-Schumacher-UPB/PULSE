#pragma once

#include <vector>
#include <string>
#include <map>
#include <fstream>
#include <iostream>
#include "cuda/typedef.cuh"

namespace PC3 {

class FileHandler {
   public:
    std::map<std::string, std::ofstream> files;
    std::string outputPath, outputName, color_palette, color_palette_phase;

    FileHandler();
    FileHandler( int argc, char** argv);
    FileHandler( FileHandler& other ) = delete;

    struct Header {
        // Spatial Parameters
        Type::real L_x, L_y;
        Type::real dx, dy;
        // Time Parameter
        Type::real t;
        // Oscillator Parameters
        Type::real t0,freq,sigma;

        Header() : L_x( 0 ), L_y( 0 ), dx( 0 ), dy( 0 ), t( 0 ), t0(0), freq(0), sigma(0) {}
        Header( Type::real L_x, Type::real L_y, Type::real dx, Type::real dy, Type::real t ) : Header() {
            this->L_x = L_x;
            this->L_y = L_y;
            this->dx = dx;
            this->dy = dy;
            this->t = t;
            this->t0 = 0;
            this->freq = 0;
            this->sigma = 0;
        }
        Header( Type::real L_x, Type::real L_y, Type::real dx, Type::real dy, Type::real t, Type::real t0, Type::real freq, Type::real sigma ) : Header() {
            this->L_x = L_x;
            this->L_y = L_y;
            this->dx = dx;
            this->dy = dy;
            this->t = t;
            this->t0 = t0;
            this->freq = freq;
            this->sigma = sigma;
        }

        friend std::ostream& operator<<( std::ostream& os, const Header& header ) {
            os << "LX " << header.L_x << " LY " << header.L_y << " DX " << header.dx << " DY " << header.dy << " TIME " << header.t;
            if (header.t0 != 0 and header.freq != 0 and header.sigma != 0)
                os << " OSC T0 " << header.t0 << " FREQ " << header.freq << " SIGMA " << header.sigma;
            return os;
        }
    };

    std::string toPath( const std::string& name );

    std::ofstream& getFile( const std::string& name );

    bool loadMatrixFromFile( const std::string& filepath, Type::complex* buffer );
    bool loadMatrixFromFile( const std::string& filepath, Type::real* buffer );

    void outputMatrixToFile( const Type::complex* buffer, unsigned int col_start, unsigned int col_stop, unsigned int row_start, unsigned int row_stop, const unsigned int N_x, const unsigned int N_y, unsigned int increment, const Header& header, std::ofstream& out, const std::string& name );
    void outputMatrixToFile( const Type::complex* buffer, unsigned int col_start, unsigned int col_stop, unsigned int row_start, unsigned int row_stop, const unsigned int N_x, const unsigned int N_y, unsigned int increment, const Header& header, const std::string& out );
    void outputMatrixToFile( const Type::complex* buffer, const unsigned int N_x, const unsigned int N_y, const Header& header, const std::string& out );
    void outputMatrixToFile( const Type::complex* buffer, const unsigned int N_x, const unsigned int N_y, const Header& header, std::ofstream& out, const std::string& name );

    void outputMatrixToFile( const Type::real* buffer, unsigned int col_start, unsigned int col_stop, unsigned int row_start, unsigned int row_stop, const unsigned int N_x, const unsigned int N_y, unsigned int increment, const Header& header, std::ofstream& out, const std::string& name );
    void outputMatrixToFile( const Type::real* buffer, unsigned int col_start, unsigned int col_stop, unsigned int row_start, unsigned int row_stop, const unsigned int N_x, const unsigned int N_y, unsigned int increment, const Header& header, const std::string& out );
    void outputMatrixToFile( const Type::real* buffer, const unsigned int N_x, const unsigned int N_y, const Header& header, const std::string& out );
    void outputMatrixToFile( const Type::real* buffer, const unsigned int N_x, const unsigned int N_y, const Header& header, std::ofstream& out, const std::string& name );

    std::vector<std::vector<Type::real>> loadListFromFile( const std::string& path, const std::string& name );
    void outputListToFile( const std::string& path, std::vector<std::vector<Type::real>>& data, const std::string& name );

    void init( int argc, char** argv );
};

std::vector<char*> readConfigFromFile(int argc, char** argv);

} // namespace PC3