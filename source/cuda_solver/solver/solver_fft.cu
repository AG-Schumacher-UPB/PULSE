#include "cuda/typedef.cuh"
#include "cuda/cuda_macro.cuh"
#include "kernel/kernel_fft.cuh"
#include "system/system.hpp"
#include "solver/gpu_solver.hpp"

#ifdef USE_CPU

    #include <fftw3.h>

    #ifdef USE_HALF_PRECISION
        using fftwplan = fftwf_plan;
        using fftwdt = fftwf_complex;
        #define fftwExecutePlan fftwf_execute_dft;

    #else
        using fftwplan = fftw_plan;
        using fftwdt = fftw_complex;
        #define fftwExecutePlan fftw_execute_dft;
    #endif

#else

    #include <cufft.h>
    #include <curand_kernel.h>
    #define cuda_fft_plan cufftHandle
    #ifdef USE_HALF_PRECISION
        #define FFTSOLVER cufftExecC2C
        #define FFTPLAN CUFFT_C2C
    #else
        #define FFTSOLVER cufftExecZ2Z
        #define FFTPLAN CUFFT_Z2Z
    #endif

#endif


#ifdef USE_CUDA
    /**
     * Static Helper Function to get the cuFFT Plan. The static variables ensure the
     * fft plan is only created once. We don't destroy the plan and hope the operating
     * system will forgive us. We could also implement a small wrapper class that
     * holds the plan and calls the destruct method when the class instance is destroyed.
    */
    static cufftHandle& getFFTPlan( size_t N_x, size_t N_y ) {
        static cufftHandle plan = 0;
        static bool isInitialized = false;

        if (not isInitialized) {
            if ( cufftPlan2d( &plan, N_x, N_y, FFTPLAN ) != CUFFT_SUCCESS ) {
                std::cout << "Error Creating CUDA FFT Plan!" << std::endl;
                return plan;
            }
            isInitialized = true;
        }

        return plan;
    }

#else

    static std::tuple<fftwplan&,fftwplan&> getFFTPlan( size_t N_x, size_t N_y, PC3::Type::complex* device_ptr_in, PC3::Type::complex* device_ptr_out ) {
        static fftwplan forward_plan;
        static fftwplan inverse_plan;
        static bool isInitialized = false;

        if (not isInitialized) {
            #ifdef USE_HALF_PRECISION
            forward_plan = fftwf_plan_dft_2d(N_x, N_y,
                                      reinterpret_cast<fftwdt*>(device_ptr_in),
                                      reinterpret_cast<fftwdt*>(device_ptr_out),
                                      FFTW_FORWARD, FFTW_ESTIMATE);
            inverse_plan = fftwf_plan_dft_2d(N_x, N_y,
                                      reinterpret_cast<fftwdt*>(device_ptr_in),
                                      reinterpret_cast<fftwdt*>(device_ptr_out),
                                      FFTW_BACKWARD, FFTW_ESTIMATE);
            #else
            forward_plan = fftw_plan_dft_2d(N_x, N_y,
                                      reinterpret_cast<fftwdt*>(device_ptr_in),
                                      reinterpret_cast<fftwdt*>(device_ptr_out),
                                      FFTW_FORWARD, FFTW_ESTIMATE);
            inverse_plan = fftw_plan_dft_2d(N_x, N_y,
                                      reinterpret_cast<fftwdt*>(device_ptr_in),
                                      reinterpret_cast<fftwdt*>(device_ptr_out),
                                      FFTW_BACKWARD, FFTW_ESTIMATE);
            #endif
            if (forward_plan == nullptr or inverse_plan == nullptr) {
                std::cout << "Error creating FFTW plans!" << std::endl;
            }
            isInitialized = true;
        }
        return std::make_tuple(std::ref(forward_plan),std::ref(inverse_plan));
    }

#endif

/*
 * This function calculates the Fast Fourier Transformation of Psi+ and Psi-
 * and saves the result in dev_fft_plus and dev_fft_minus. These values can
 * then be grabbed using the getDeviceArrays() function. The FFT is then
 * shifted such that k = 0 is in the center of the FFT matrix. Then, the
 * FFT Filter is applied to the FFT, and the FFT is shifted back. Finally,
 * the inverse FFT is calculated and the result is saved in dev_current_Psi_Plus
 * and dev_current_Psi_Minus. The FFT Arrays are shifted once again for
 * visualization purposes.
 * NOTE/OPTIMIZATION: The Shift->Filter->Shift function will be changed later
 * to a cached filter mask, which itself will be shifted.
 */
void PC3::Solver::applyFFTFilter( dim3 block_size, dim3 grid_size, bool apply_mask ) {
    
    // Calculate the actual FFTs
    calculateFFT( matrix.wavefunction_plus.getDevicePtr(), matrix.fft_plus.getDevicePtr(), FFT::forward );

    // For now, we shift, transform, shift the results. TODO: Move this into one function without shifting
    // Shift FFT to center k = 0
    CALL_KERNEL( PC3::Kernel::fft_shift_2D, "FFT Shift Plus", grid_size, block_size, 
        matrix.fft_plus.getDevicePtr(), system.p.N_x, system.p.N_y 
    );

    // Do the FFT and the shifting here already for visualization only
    if ( system.p.use_twin_mode ) {
        calculateFFT( matrix.wavefunction_minus.getDevicePtr(), matrix.fft_minus.getDevicePtr(), FFT::forward );
        
        CALL_KERNEL( PC3::Kernel::fft_shift_2D, "FFT Shift Minus", grid_size, block_size, 
            matrix.fft_minus.getDevicePtr(), system.p.N_x, system.p.N_y 
        );
    }
    
    if (not apply_mask)
        return;
    
    // Apply the FFT Mask Filter
    CALL_KERNEL(PC3::Kernel::kernel_mask_fft, "FFT Mask Plus", grid_size, block_size, 
        matrix.fft_plus.getDevicePtr(), matrix.fft_mask_plus.getDevicePtr(), system.p.N_x*system.p.N_y
    );
    
    // Undo the shift
    CALL_KERNEL( PC3::Kernel::fft_shift_2D, "FFT Shift Plus", grid_size, block_size, 
         matrix.fft_plus.getDevicePtr(), system.p.N_x, system.p.N_y 
    );

    // Transform back.
    calculateFFT(  matrix.fft_plus.getDevicePtr(), matrix.wavefunction_plus.getDevicePtr(), FFT::inverse );
    
    // Shift FFT Once again for visualization
    CALL_KERNEL( PC3::Kernel::fft_shift_2D, "FFT Shift Plus", grid_size, block_size, 
        matrix.fft_plus.getDevicePtr(), system.p.N_x, system.p.N_y 
    );
    
    // Do the same for the minus component
    if (not system.p.use_twin_mode)
        return;

    CALL_KERNEL(PC3::Kernel::kernel_mask_fft, "FFT Mask Plus", grid_size, block_size, 
        matrix.fft_minus.getDevicePtr(), matrix.fft_mask_minus.getDevicePtr(), system.p.N_x*system.p.N_y 
    );

    CALL_KERNEL( PC3::Kernel::fft_shift_2D, "FFT Minus Plus", grid_size, block_size, 
        matrix.fft_minus.getDevicePtr(), system.p.N_x,system.p.N_y 
    );
    
    calculateFFT( matrix.fft_minus.getDevicePtr(), matrix.wavefunction_minus.getDevicePtr(), FFT::inverse );

    CALL_KERNEL( PC3::Kernel::fft_shift_2D, "FFT Minus Plus", grid_size, block_size, 
        matrix.fft_minus.getDevicePtr(), system.p.N_x,system.p.N_y 
    );

}

void PC3::Solver::calculateFFT( Type::complex* device_ptr_in, Type::complex* device_ptr_out, FFT dir ) {
    #ifdef USE_CUDA
        // Do FFT using CUDAs FFT functions
        auto plan = getFFTPlan( system.p.N_x, system.p.N_y );
        CHECK_CUDA_ERROR( FFTSOLVER( plan, reinterpret_cast<cufftComplex*>(device_ptr_in), reinterpret_cast<cufftComplex*>(device_ptr_out), dir == FFT::inverse ? CUFFT_INVERSE : CUFFT_FORWARD ), "FFT Exec" );
    #else   
        auto [plan_forward, plan_inverse] = getFFTPlan(system.p.N_x, system.p.N_y, device_ptr_in, device_ptr_out);
        // Do FFT on CPU using external Library.
        int index = system.p.N2 / 2;
        std::cout << "Before In: " << device_ptr_in[index] << " Out: " << device_ptr_out[index] <<  std::endl;
        fftwExecutePlan(dir == FFT::inverse ? plan_inverse : plan_forward, reinterpret_cast<fftwdt*>(device_ptr_in), reinterpret_cast<fftwdt*>(device_ptr_out));
        std::cout << "After In: " << device_ptr_in[index] << " Out: " << device_ptr_out[index] <<  std::endl;
        
    #endif
}