/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <iostream>
#include <cstdlib>

#include <chrono>
#include <thread>

// External library for easier parsing of CLI arguments by the executable
#include <boost/program_options.hpp>

// Coyote-specific includes
#include "cBench.hpp"
#include "cThread.hpp"
#include "constants.hpp"

constexpr bool const IS_CLIENT = true;

// Note, how the Coyote thread is passed by reference; to avoid creating a copy of 
// the thread object which can lead to undefined behaviour and bugs. 
void run_write_only(
    coyote::cThread &coyote_thread, coyote::rdmaSg &sg, 
    int *mem, uint n_runs
) {
    // When writing, the server asserts the written payload is correct (which the client sets)
    // When reading, the client asserts the read payload is correct (which the server sets)
    for (uint i = 0; i < sg.len / sizeof(int); i++) {
        mem[i] = i;         
    }
    
    // Before every benchmark, clear previous completion flags and sync with server
    // Sync is in a way equivalent to MPI_Barrier()
    
    coyote_thread.clearCompleted();
    coyote_thread.connSync(IS_CLIENT);
    
    
    /* Benchmark function; as eplained in the README
     * For RDMA_WRITEs, the client writes multiple times to the server and then the server writes the same content back
     * For RDMA READs, the client reads from the server multiple times
     * In boths cases, that means there will be n_transfers completed writes to local memory (LOCAL_WRITE)
     */
          
    for (uint i = 0; i < n_runs; i++) {
        coyote_thread.invoke(coyote::CoyoteOper::REMOTE_RDMA_WRITE, sg);
    }
    using namespace std::chrono_literals;
    while (coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != 1) {
        std::cout << "client waiting on " << coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " completed writes\n" << std::flush;
        std::this_thread::sleep_for(1s);
        std::cout << "cool\n" << std::flush;
    }
}

int main(int argc, char *argv[])  {
    std::string server_ip;
    unsigned int size, n_runs;

    boost::program_options::options_description runtime_options("Coyote Perf RDMA Options");
    runtime_options.add_options()
        ("ip_address,i", boost::program_options::value<std::string>(&server_ip), "Server's IP address")
        ("runs,r", boost::program_options::value<unsigned int>(&n_runs)->default_value(N_RUNS_DEFAULT), "Number of times to repeat the test")
        ("size,x", boost::program_options::value<unsigned int>(&size)->default_value(64), "Starting (minimum) transfer size");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    if (server_ip.empty()) {
        std::cerr << "Error: server IP must be specified with -i\n";
        return EXIT_FAILURE;
    }

    coyote::cThread coyote_thread(DEFAULT_VFPGA_ID, getpid(), 0);
    int *mem = (int *) coyote_thread.initRDMA(size, coyote::DEF_PORT, server_ip.c_str());
    if (!mem) { throw std::runtime_error("Could not allocate memory; exiting..."); }

    HEADER("RDMA BENCHMARK: CLIENT");
    coyote::rdmaSg sg = { .len = size };

    run_write_only(
        coyote_thread,
        sg,
        mem,
        n_runs
    );
    
    std::cout << "very cool\n" << std::flush;
    coyote_thread.connSync(IS_CLIENT);
    return EXIT_SUCCESS;
}