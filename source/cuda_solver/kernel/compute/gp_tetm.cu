#include "kernel/kernel_compute.cuh"
#include "kernel/kernel_hamilton.cuh"
#include "kernel/kernel_index_overwrite.cuh"

PULSE_GLOBAL void PC3::Kernel::Compute::gp_tetm( int i, Type::real t, MatrixContainer::Pointers dev_ptrs, SystemParameters::KernelParameters p_in, Solver::TemporalEvelope::Pointers oscillation_pulse, Solver::TemporalEvelope::Pointers oscillation_pump, Solver::TemporalEvelope::Pointers oscillation_potential, InputOutput io ) {
    
    LOCAL_SHARE_STRUCT( SystemParameters::KernelParameters, p_in, p );
    
    OVERWRITE_THREAD_INDEX( i );

    const int row = i / p.N_x;
    const int col = i % p.N_x;

    const auto in_wf_plus = io.in_wf_plus[i];
    const auto in_wf_minus = io.in_wf_minus[i];

    Type::complex hamilton_regular_plus = p.m2_over_dx2_p_dy2 * in_wf_plus;
    Type::complex hamilton_regular_minus = p.m2_over_dx2_p_dy2 * in_wf_minus;
    Type::complex hamilton_cross_plus, hamilton_cross_minus;
    PC3::Kernel::Hamilton::tetm_neighbours_plus( hamilton_regular_plus, hamilton_cross_minus, io.in_wf_plus, i, row, col, p.N_x, p.N_y, p.dx, p.dy, p.periodic_boundary_x, p.periodic_boundary_y );
    PC3::Kernel::Hamilton::tetm_neighbours_minus( hamilton_regular_minus, hamilton_cross_plus, io.in_wf_minus, i, row, col, p.N_x, p.N_y, p.dx, p.dy, p.periodic_boundary_x, p.periodic_boundary_y );

    const auto in_rv_plus = io.in_rv_plus[i];
    const auto in_rv_minus = io.in_rv_minus[i];
    const Type::real in_psi_plus_norm = CUDA::abs2( in_wf_plus );
    const Type::real in_psi_minus_norm = CUDA::abs2( in_wf_minus );
 
    // MARK: Wavefunction Plus
    Type::complex result = p.minus_i_over_h_bar_s * p.m_eff_scaled * hamilton_regular_plus;
    
    for (int k = 0; k < oscillation_potential.n; k++) {
        const size_t offset = k * p.N_x * p.N_y;
        const Type::complex potential = dev_ptrs.potential_plus[i+offset] * oscillation_potential.amp[k];
        result += p.minus_i_over_h_bar_s * potential * in_wf_plus;
    }

    result += p.minus_i_over_h_bar_s * p.g_c * in_psi_plus_norm * in_wf_plus;
    result += p.minus_i_over_h_bar_s * p.g_r * in_rv_plus * in_wf_plus;
    result += Type::real(0.5) * p.R * in_rv_plus * in_wf_plus;
    result -= Type::real(0.5)* p.gamma_c * in_wf_plus;

    result += p.minus_i_over_h_bar_s * p.g_pm * in_psi_minus_norm * in_wf_plus;
    result += p.minus_i_over_h_bar_s * p.delta_LT * hamilton_cross_plus;
    
    // MARK: Pulse Plus
    for (int k = 0; k < oscillation_pulse.n; k++) {
        const size_t offset = k * p.N_x * p.N_y;
        const Type::complex pulse = dev_ptrs.pulse_plus[i+offset];
        result += p.one_over_h_bar_s * pulse * oscillation_pulse.amp[k];
    }

    // MARK: Stochastic
    if (p.stochastic_amplitude > 0.0) {
        const Type::complex dw = dev_ptrs.random_number[i] * CUDA::sqrt( ( p.R * in_rv_plus + p.gamma_c ) / (Type::real(4.0) * p.dV) );
        result -= p.minus_i_over_h_bar_s * p.g_c * in_wf_plus / p.dV - dw / p.dt;
    }

    io.out_wf_plus[i] = result;

    // MARK: Reservoir Plus
    result = -( p.gamma_r + p.R * in_psi_plus_norm ) * in_rv_plus;

    for (int k = 0; k < oscillation_pump.n; k++) {
        const size_t offset = k * p.N_x * p.N_y;
        const auto gauss = oscillation_pump.amp[k];
        result += dev_ptrs.pump_plus[i+offset] * gauss;
    }

    // MARK: Stochastic-2
    if (p.stochastic_amplitude > 0.0)
        result += p.R * in_rv_plus / p.dV;

    io.out_rv_plus[i] = result;
    

    // MARK: Wavefunction Minus
    result = p.minus_i_over_h_bar_s * p.m_eff_scaled * hamilton_regular_minus;
    
    for (int k = 0; k < oscillation_potential.n; k++) {
        const size_t offset = k * p.N_x * p.N_y;
        const Type::complex potential = dev_ptrs.potential_minus[i+offset] * oscillation_potential.amp[k];
        result += p.minus_i_over_h_bar_s * potential * in_wf_minus;
    }

    result += p.minus_i_over_h_bar_s * p.g_c * in_psi_minus_norm * in_wf_minus;
    result += p.minus_i_over_h_bar_s * p.g_r * in_rv_minus * in_wf_minus;
    result += Type::real(0.5) * p.R * in_rv_minus * in_wf_minus;
    result -= Type::real(0.5) * p.gamma_c * in_wf_minus;
 
    result += p.minus_i_over_h_bar_s * p.g_pm * in_psi_plus_norm * in_wf_minus;
    result += p.minus_i_over_h_bar_s * p.delta_LT * hamilton_cross_minus;

    // MARK: Pulse Minus
    for (int k = 0; k < oscillation_pulse.n; k++) {
        const size_t offset = k * p.N_x * p.N_y;
        const Type::complex pulse = dev_ptrs.pulse_minus[i+offset];
        result += p.one_over_h_bar_s * pulse * oscillation_pulse.amp[k];
    }

    if (p.stochastic_amplitude > 0.0) {
        const Type::complex dw = dev_ptrs.random_number[i] * CUDA::sqrt( ( p.R * in_rv_minus + p.gamma_c ) / (Type::real(4.0) * p.dV) );
        result -= p.minus_i_over_h_bar_s * p.g_c * in_wf_minus / p.dV - dw / p.dt;
    }

    io.out_wf_minus[i] = result;

    // MARK: Reservoir Minus
    result = -( p.gamma_r + p.R * in_psi_minus_norm ) * in_rv_minus;

    for (int k = 0; k < oscillation_pump.n; k++) {
        const size_t offset = k * p.N_x * p.N_y;
        const auto gauss = oscillation_pump.amp[k];
        result += dev_ptrs.pump_minus[i+offset] * gauss;
    }

    // MARK: Stochastic-2
    if (p.stochastic_amplitude > 0.0)
        result += p.R * in_rv_minus / p.dV;

    io.out_rv_minus[i] = result;

}

/**
 * Linear, Nonlinear and Independet parts of the upper Kernel
 * These isolated implementations serve for the Split Step
 * Fourier Method (SSFM)
*/

PULSE_GLOBAL void PC3::Kernel::Compute::gp_tetm_linear_fourier( int i, Type::real t, Type::complex dtc, MatrixContainer::Pointers dev_ptrs, SystemParameters::KernelParameters p, Solver::TemporalEvelope::Pointers oscillation_pulse, Solver::TemporalEvelope::Pointers oscillation_pump, Solver::TemporalEvelope::Pointers oscillation_potential, InputOutput io ) {
    
    OVERWRITE_THREAD_INDEX( i );

    // We do some weird looking casting to avoid intermediate casts to size_t
    Type::real row = Type::real(size_t(i / p.N_x));
    Type::real col = Type::real(size_t(i % p.N_x));
    
    const Type::real k_x = 2.0*3.1415926535 * Type::real(col <= p.N_x/2 ? col : -Type::real(p.N_x) + col)/p.L_x;
    const Type::real k_y = 2.0*3.1415926535 * Type::real(row <= p.N_y/2 ? row : -Type::real(p.N_y) + row)/p.L_y;

    Type::real linear = p.h_bar_s/2.0/p.m_eff * (k_x*k_x + k_y*k_y);
    io.out_wf_plus[i] = io.in_wf_plus[i] / Type::real(p.N2) * CUDA::exp( p.minus_i * linear * dtc / Type::real(2.0) );
    io.out_wf_minus[i] = io.in_wf_minus[i] / Type::real(p.N2) * CUDA::exp( p.minus_i * linear * dtc / Type::real(2.0) );
}

PULSE_GLOBAL void PC3::Kernel::Compute::gp_tetm_nonlinear( int i, Type::real t, Type::complex dtc, MatrixContainer::Pointers dev_ptrs, SystemParameters::KernelParameters p, Solver::TemporalEvelope::Pointers oscillation_pulse, Solver::TemporalEvelope::Pointers oscillation_pump, Solver::TemporalEvelope::Pointers oscillation_potential, InputOutput io ) {
    
    OVERWRITE_THREAD_INDEX( i );
    
    const Type::complex in_wf_plus = io.in_wf_plus[i];
    const Type::complex in_rv_plus = io.in_rv_plus[i];
    const Type::complex in_wf_minus = io.in_wf_minus[i];
    const Type::complex in_rv_minus = io.in_rv_minus[i];
    const Type::real in_psi_plus_norm = CUDA::abs2( in_wf_plus );
    const Type::real in_psi_minus_norm = CUDA::abs2( in_wf_minus );
    
    // MARK: Wavefunction Plus
    Type::complex result = {p.g_c * in_psi_plus_norm, -p.h_bar_s * Type::real(0.5) * p.gamma_c};

    for (int k = 0; k < oscillation_potential.n; k++) {
        const size_t offset = k * p.N_x * p.N_y;
        const Type::complex potential = dev_ptrs.potential_plus[i+offset] * oscillation_potential.amp[k]; //CUDA::gaussian_oscillator(t, oscillation_potential.t0[k], oscillation_potential.sigma[k], oscillation_potential.freq[k]);
        result += potential;
    }

    result += p.g_r * in_rv_plus;
    result += p.i * p.h_bar_s * Type::real(0.5) * p.R * in_rv_plus;

    Type::complex cross = p.g_pm * in_psi_minus_norm;
    //cross += p.delta_LT * hamilton_cross_plus;

    // MARK: Stochastic
    if (p.stochastic_amplitude > 0.0) {
        const Type::complex dw = dev_ptrs.random_number[i] * CUDA::sqrt( ( p.R * in_rv_plus + p.gamma_c ) / (Type::real(4.0) * p.dV) );
        result -= p.g_c / p.dV;
    }

    io.out_wf_plus[i] = in_wf_plus * CUDA::exp(p.minus_i_over_h_bar_s * ( result + cross) * dtc);

    // MARK: Reservoir
    result = -p.gamma_r * in_rv_plus;
    result -= p.R * in_psi_plus_norm * in_rv_plus;
    for (int k = 0; k < oscillation_pump.n; k++) {
        const int offset = k * p.N_x * p.N_y;
        result += dev_ptrs.pump_plus[i+offset] * oscillation_pump.amp[k]; //CUDA::gaussian_oscillator(t, oscillation_pump.t0[k], oscillation_pump.sigma[k], oscillation_pump.freq[k]);
    }
    // MARK: Stochastic-2
    if (p.stochastic_amplitude > 0.0)
        result += p.R * in_rv_plus / p.dV;
    io.out_rv_plus[i] = in_rv_plus + result * dtc;

    // MARK: Wavefunction Minus
    result = Type::complex(p.g_c * in_psi_minus_norm, -p.h_bar_s * Type::real(0.5) * p.gamma_c);

    for (int k = 0; k < oscillation_potential.n; k++) {
        const size_t offset = k * p.N_x * p.N_y;
        const Type::complex potential = dev_ptrs.potential_minus[i+offset] * oscillation_potential.amp[k]; //CUDA::gaussian_oscillator(t, oscillation_potential.t0[k], oscillation_potential.sigma[k], oscillation_potential.freq[k]);
        result += potential;
    }

    result += p.g_r * in_rv_minus;
    result += p.i * p.h_bar_s * Type::real(0.5) * p.R * in_rv_minus;

    cross = p.g_pm * in_psi_plus_norm;
    //cross += p.delta_LT * hamilton_cross_minus;

    // MARK: Stochastic
    if (p.stochastic_amplitude > 0.0) {
        const Type::complex dw = dev_ptrs.random_number[i] * CUDA::sqrt( ( p.R * in_rv_minus + p.gamma_c ) / (Type::real(4.0) * p.dV) );
        result -= p.g_c / p.dV;
    }

    io.out_wf_minus[i] = in_wf_minus * CUDA::exp(p.minus_i_over_h_bar_s * ( result + cross ) * dtc);

    // MARK: Reservoir
    result = -p.gamma_r * in_rv_minus;
    result -= p.R * in_psi_minus_norm * in_rv_minus;
    for (int k = 0; k < oscillation_pump.n; k++) {
        const int offset = k * p.N_x * p.N_y;
        result += dev_ptrs.pump_minus[i+offset] * oscillation_pump.amp[k]; //CUDA::gaussian_oscillator(t, oscillation_pump.t0[k], oscillation_pump.sigma[k], oscillation_pump.freq[k]);
    }
    // MARK: Stochastic-2
    if (p.stochastic_amplitude > 0.0)
        result += p.R * in_rv_minus / p.dV;
    io.out_rv_minus[i] = in_rv_minus + result * dtc;
}

PULSE_GLOBAL void PC3::Kernel::Compute::gp_tetm_independent( int i, Type::real t, Type::complex dtc, MatrixContainer::Pointers dev_ptrs, SystemParameters::KernelParameters p, Solver::TemporalEvelope::Pointers oscillation_pulse, Solver::TemporalEvelope::Pointers oscillation_pump, Solver::TemporalEvelope::Pointers oscillation_potential, InputOutput io ) {
    
    OVERWRITE_THREAD_INDEX( i );

    // MARK: Plus
    Type::complex result = {0.0,0.0};

    // MARK: Pulse
    for (int k = 0; k < oscillation_pulse.n; k++) {
        const size_t offset = k * p.N_x * p.N_y;
        const Type::complex pulse = dev_ptrs.pulse_plus[i+offset];
        result += p.minus_i_over_h_bar_s * dtc * pulse * oscillation_pulse.amp[k]; //CUDA::gaussian_complex_oscillator(t, oscillation_pulse.t0[k], oscillation_pulse.sigma[k], oscillation_pulse.freq[k]);
    }
    if (p.stochastic_amplitude > 0.0) {
        const Type::complex in_rv = io.in_rv_plus[i];
        const Type::complex dw = dev_ptrs.random_number[i] * CUDA::sqrt( ( p.R * in_rv + p.gamma_c ) / (Type::real(4.0) * p.dV) );
        result += dw;
    }
    io.out_wf_plus[i] = io.in_wf_plus[i] + result;

    // MARK: Minus
    result = 0.0;

    // MARK: Pulse
    for (int k = 0; k < oscillation_pulse.n; k++) {
        const size_t offset = k * p.N_x * p.N_y;
        const Type::complex pulse = dev_ptrs.pulse_minus[i+offset];
        result += p.minus_i_over_h_bar_s * dtc * pulse * oscillation_pulse.amp[k]; //CUDA::gaussian_complex_oscillator(t, oscillation_pulse.t0[k], oscillation_pulse.sigma[k], oscillation_pulse.freq[k]);
    }
    if (p.stochastic_amplitude > 0.0) {
        const Type::complex in_rv = io.in_rv_minus[i];
        const Type::complex dw = dev_ptrs.random_number[i] * CUDA::sqrt( ( p.R * in_rv + p.gamma_c ) / (Type::real(4.0) * p.dV) );
        result += dw;
    }
    io.out_wf_minus[i] = io.in_wf_minus[i] + result;
}