#include <cmath>
#include <iostream>
#include <fstream>
#include <complex>
#include <vector>
#include <cstdlib>
#include <omp.h>
#include <chrono>

#include "system.hpp"
#include "kernel.hpp"
#include "helperfunctions.hpp"
#include "timeit.hpp"
#include "sfml_helper.hpp"

using namespace std::complex_literals;
using Scalar = std::complex<double>;

int main( int argc, char* argv[] ) {
    // Convert input arguments to system and handler variables
    auto [system, filehandler] = initializeSystem( argc, argv );
    auto buffer = Buffer( system.s_N /*Matrix Size*/ );

    // Initialize Buffer Arrays
    // This way of generating the initial state can be replaced by e.g. random initialization in the future
    generateRingPhase( system.s_N, 1.0, system.m_plus, system.xmax / 10, system.xmax / 10, 0.0, 0.0, system.xmax, system.dx, system.normalize_phase_states, buffer.Psi_Plus, true /*reset to zero*/ );
    generateRingPhase( system.s_N, 1.0, system.m_minus, system.xmax / 10, system.xmax / 10, 0.0, 0.0, system.xmax, system.dx, system.normalize_phase_states, buffer.Psi_Minus, true /*reset to zero*/ );
    for ( int i = 0; i < system.s_N * system.s_N; i++ ) {
        buffer.n_Plus[i] = cwiseAbs2( buffer.Psi_Plus[i] );
        buffer.n_Minus[i] = cwiseAbs2( buffer.Psi_Minus[i] );
    }

    // Load Matrices from File. If --load was not passed in argv, this method does nothing.
    filehandler.loadMatrices( system, buffer );

    // Copy pump to device
    initializePumpVariables( system );
    initializePulseVariables( system );

    // Create Main Plotwindow. Needs to be compiled with -DSFML_RENDER
    initSFMLWindow( system, filehandler );

    // TODO: das hier in eine funktion und dann nur system übergeben!
    initializeDeviceVariables( system.dx, system.dt, system.g_r, system.s_N, system.m_eff, system.gamma_c, system.g_c, system.g_pm, system.gamma_r, system.R, system.delta_LT, system.xmax, system.h_bar_s );
    initializeDeviceArrays( system.s_N );

    // Move Initial State to the GPU
    setDeviceArrays( buffer.Psi_Plus, buffer.Psi_Minus, buffer.n_Plus, buffer.n_Minus, system.s_N );

    bool running = true;
    // Main Loop
    while ( system.t < system.t_max and running ) {
        timeit(
            // The CPU should briefly evaluate wether the pulses have to be evaluated
            bool evaluate_pulse = doEvaluatePulse( system );
            // Iterate #out_modulo times
            for ( int i = 0; i < filehandler.out_modulo; i++ ) {
                rungeFunctionIterate( system, evaluate_pulse );
            },
            "Main" );

        timeit(
            getDeviceArrays( buffer.Psi_Plus, buffer.Psi_Minus, buffer.n_Plus, buffer.n_Minus, buffer.fft_plus, buffer.fft_minus, system.s_N );
            cacheValues( system, buffer );
            running = plotSFMLWindow( system, filehandler, buffer );
            , "Plotting" );

        double duration = timeitGet( "Main" ) + timeitGet( "Plotting" );
        auto [min,max] = minmax( buffer.Psi_Plus, system.s_N * system.s_N );
        std::cout << "T = " << int( system.t ) << ", Time per " << filehandler.out_modulo << " iterations: " << duration << "s -> " << 1. / (duration)*system.dt * filehandler.out_modulo << "ps/s, current dt = " << system.dt << "                \r";
    }

    // Get final state from GPU
    getDeviceArrays( buffer.Psi_Plus, buffer.Psi_Minus, buffer.n_Plus, buffer.n_Minus, buffer.fft_plus, buffer.fft_minus, system.s_N );

    // Fileoutput
    filehandler.outputMatrices( system, buffer );
    filehandler.cacheToFiles( buffer );

    // Free Device Memory
    freeDeviceArrays();

    // Print Time statistics and output to file
    timeitStatisticsSummary( system, filehandler );
    timeitToFile( filehandler.getFile("times") );

    return 0;
}