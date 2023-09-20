#include "helperfunctions.hpp"
#ifndef USECPU
#include <thrust/extrema.h>
#include <thrust/execution_policy.h>
#include <thrust/pair.h>
#include <thrust/device_ptr.h>
#else
#include <ranges>
#include <algorithm>
#endif
#include "cuda_complex.cuh"

std::tuple<real_number, real_number> minmax( complex_number* buffer, int size, bool device_pointer ) {
    #ifndef USECPU
    if ( device_pointer ) {
        thrust::device_ptr<complex_number> dev_buffer = thrust::device_pointer_cast( buffer );
        auto mm = thrust::minmax_element( thrust::device, dev_buffer, dev_buffer + size, compare_complex_abs2() );
        complex_number min = *mm.first;
        complex_number max = *mm.second;
        return std::make_tuple( min.x * min.x + min.y * min.y, max.x * max.x + max.y * max.y );
    }
    const auto [first, second] = thrust::minmax_element( buffer, buffer + size, compare_complex_abs2() );
    #else
    const auto [first, second] = std::ranges::minmax_element( buffer, buffer + size, compare_complex_abs2() );
    #endif
    return std::make_tuple( real( *first ) * real( *first ) + imag( *first ) * imag( *first ), real( *second ) * real( *second ) + imag( *second ) * imag( *second ) );
}
std::tuple<real_number, real_number> minmax( real_number* buffer, int size, bool device_pointer ) {
    #ifndef USECPU
    if (device_pointer) {
        thrust::device_ptr<real_number> dev_buffer = thrust::device_pointer_cast(buffer);
        auto mm = thrust::minmax_element( thrust::device, dev_buffer, dev_buffer + size, thrust::less<real_number>() );
        real_number min = *mm.first;
        real_number max = *mm.second;
        return std::make_tuple( min, max );
    }
    const auto [first, second] = thrust::minmax_element( buffer, buffer + size, thrust::less<real_number>() );
    #else
    const auto [first, second] = std::ranges::minmax_element( buffer, buffer + size, std::less<real_number>() );
    #endif
    return std::make_tuple( *first, *second );
}