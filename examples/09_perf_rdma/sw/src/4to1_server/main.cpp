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
#include "cThread.hpp"
#include "constants.hpp"

constexpr bool const IS_CLIENT = false;

// Note, how the Coyote thread is passed by reference; to avoid creating a copy of 
// the thread object which can lead to undefined behaviour and bugs. 
void run_4_to_1_server(
    coyote::cThread &coyote_thread_1, coyote::cThread &coyote_thread_2, coyote::cThread &coyote_thread_3, coyote::cThread &coyote_thread_4, coyote::rdmaSg &sg, int *mem1, int *mem2, int *mem3, int *mem4, uint n_runs
) {
    coyote_thread_1.clearCompleted();
    coyote_thread_1.connSync(IS_CLIENT);
    std::cout << "synced with client 1\n" << std::flush;

    // Wait for client writes to complete
    while (coyote_thread_1.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != n_runs) {
        //std::cout << "server received " << coyote_thread_1.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " completed writes\n" << std::flush;
        //std::this_thread::sleep_for(1s);
    }
    std::cout << "server received " << coyote_thread_1.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " completed writes\n" << std::flush;
    std::cout << "Phase 1 done\n" << std::flush;

    coyote_thread_1.clearCompleted();
    coyote_thread_1.connSync(IS_CLIENT);

    coyote_thread_2.clearCompleted();
    coyote_thread_2.connSync(IS_CLIENT);

    std::cout << "starting Phase 2\n" << std::flush;

    while (coyote_thread_1.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != n_runs || 
    coyote_thread_2.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != n_runs) {
        //std::cout << "server received " << coyote_thread_1.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " completed writes from client 1 and " 
        //<< coyote_thread_2.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " completed writes from client 2.\n" << std::flush;
        //std::this_thread::sleep_for(1s);
    }
    std::cout << "server received " << coyote_thread_1.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " completed writes from client 1 and " 
    << coyote_thread_2.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " completed writes from client 2.\n" << std::flush;
    std::cout << "Phase 2 done\n" << std::flush;
    coyote_thread_1.clearCompleted();
    coyote_thread_1.connSync(IS_CLIENT);

    coyote_thread_2.clearCompleted();
    coyote_thread_2.connSync(IS_CLIENT);

    coyote_thread_3.clearCompleted();
    coyote_thread_3.connSync(IS_CLIENT);
    std::cout << "starting Phase 3\n" << std::flush;

    while (coyote_thread_1.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != n_runs ||
           coyote_thread_2.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != n_runs ||
           coyote_thread_3.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != n_runs ) {
        //std::cout << "server received " << coyote_thread_1.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << ", "
        //<< coyote_thread_2.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " and " 
        //<< coyote_thread_3.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " completed writes from client 1, 2 and 3.\n" << std::flush;
        //std::this_thread::sleep_for(1s);
    }
    std::cout << "server received " << coyote_thread_1.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << ", "
    << coyote_thread_2.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " and " 
    << coyote_thread_3.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " completed writes from client 1, 2 and 3.\n" << std::flush;
    std::cout << "Phase 3 done\n" << std::flush;
    coyote_thread_1.clearCompleted();
    coyote_thread_1.connSync(IS_CLIENT);

    coyote_thread_2.clearCompleted();
    coyote_thread_2.connSync(IS_CLIENT);

    coyote_thread_3.clearCompleted();
    coyote_thread_3.connSync(IS_CLIENT);

    coyote_thread_4.clearCompleted();
    coyote_thread_4.connSync(IS_CLIENT);
    std::cout << "starting Phase 4\n" << std::flush;

    while (coyote_thread_1.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != n_runs ||
           coyote_thread_2.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != n_runs ||
           coyote_thread_3.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != n_runs ||
           coyote_thread_4.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != n_runs) {
        //std::cout << "server received " << coyote_thread_1.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << ", "
        //<< coyote_thread_2.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << ", " 
        //<< coyote_thread_3.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " and " 
        //<< coyote_thread_4.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " completed writes from client 1, 2, 3 and 4.\n" << std::flush;
        //std::this_thread::sleep_for(1s);
    }
    std::cout << "server received " << coyote_thread_1.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << ", "
    << coyote_thread_2.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << ", " 
    << coyote_thread_3.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " and " 
    << coyote_thread_4.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " completed writes from client 1, 2, 3 and 4.\n" << std::flush;
    std::cout << "Phase 4 done\n" << std::flush;
    coyote_thread_1.clearCompleted();
    coyote_thread_1.connSync(IS_CLIENT);

    coyote_thread_2.clearCompleted();
    coyote_thread_2.connSync(IS_CLIENT);

    coyote_thread_3.clearCompleted();
    coyote_thread_3.connSync(IS_CLIENT);

    coyote_thread_4.clearCompleted();
    coyote_thread_4.connSync(IS_CLIENT);
    std::cout << "starting Phase 5\n" << std::flush;

    while (coyote_thread_2.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != n_runs ||
           coyote_thread_3.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != n_runs ||
           coyote_thread_4.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != n_runs) {
        //std::cout << "server received " <<  coyote_thread_2.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << ", " 
        //<< coyote_thread_3.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " and " 
        //<< coyote_thread_4.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " completed writes from client 2, 3 and 4.\n" << std::flush;
        //std::this_thread::sleep_for(1s);
    }
    std::cout << "server received " <<  coyote_thread_2.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << ", " 
    << coyote_thread_3.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " and " 
    << coyote_thread_4.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " completed writes from client 2, 3 and 4.\n" << std::flush;
    std::cout << "Phase 5 done\n" << std::flush;

    coyote_thread_2.clearCompleted();
    coyote_thread_2.connSync(IS_CLIENT);

    coyote_thread_3.clearCompleted();
    coyote_thread_3.connSync(IS_CLIENT);

    coyote_thread_4.clearCompleted();
    coyote_thread_4.connSync(IS_CLIENT);
    std::cout << "starting Phase 6\n" << std::flush;

    while (coyote_thread_3.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != n_runs ||
           coyote_thread_4.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != n_runs) {
        //std::cout << "server received " <<  coyote_thread_3.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " and " 
        //<< coyote_thread_4.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " completed writes from client 3 and 4.\n" << std::flush;
        //std::this_thread::sleep_for(1s);
    }
    std::cout << "server received " <<  coyote_thread_3.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " and " 
    << coyote_thread_4.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " completed writes from client 3 and 4.\n" << std::flush;
    std::cout << "Phase 6 done\n" << std::flush;

    coyote_thread_3.clearCompleted();
    coyote_thread_3.connSync(IS_CLIENT);

    coyote_thread_4.clearCompleted();
    coyote_thread_4.connSync(IS_CLIENT);
    std::cout << "starting Phase 7\n" << std::flush;

        while (coyote_thread_4.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != n_runs) {
        //std::cout << "server received " << coyote_thread_4.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " completed writes from client 4.\n" << std::flush;
        //std::this_thread::sleep_for(1s);
    }
    std::cout << "server received " << coyote_thread_4.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) << " completed writes from client 4.\n" << std::flush;
    std::cout << "Phase 7 done\n" << std::flush;

    coyote_thread_4.clearCompleted();
    coyote_thread_4.connSync(IS_CLIENT);
}


int main(int argc, char *argv[])  {
    // CLI arguments
    unsigned int size, n_runs;

    boost::program_options::options_description runtime_options("Coyote Perf RDMA Options");
    runtime_options.add_options()
        ("runs,r", boost::program_options::value<unsigned int>(&n_runs)->default_value(N_RUNS_DEFAULT), "Number of times to repeat the test")
        ("size,x", boost::program_options::value<unsigned int>(&size)->default_value(64), "Starting (minimum) transfer size");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    std::cout << "server invoking cThreads\n" << std::flush;
    // Allocate Coyothe threa and set-up RDMA connections, buffer etc.
    // initRDMA is explained in more detail in client/main.cpp
    coyote::cThread coyote_thread_1(DEFAULT_VFPGA_ID, getpid());
    int *mem1 = (int *) coyote_thread_1.initRDMA(size, coyote::DEF_PORT);
    if (!mem1) { throw std::runtime_error("Could not allocate memory for thread 1; exiting..."); }

    std::cout << "first client connected\n" << std::flush;

    coyote::cThread coyote_thread_2(DEFAULT_VFPGA_ID, getpid());
    int *mem2 = (int *) coyote_thread_2.initRDMA(size, coyote::DEF_PORT+1);
    if (!mem2) { throw std::runtime_error("Could not allocate memory for thread 2; exiting..."); }

    std::cout << "second client connected\n" << std::flush;

    coyote::cThread coyote_thread_3(DEFAULT_VFPGA_ID, getpid());
    int *mem3 = (int *) coyote_thread_3.initRDMA(size, coyote::DEF_PORT+2);
    if (!mem3) { throw std::runtime_error("Could not allocate memory for thread 3; exiting..."); }

    std::cout << "third client connected\n" << std::flush;

    coyote::cThread coyote_thread_4(DEFAULT_VFPGA_ID, getpid());
    int *mem4 = (int *) coyote_thread_4.initRDMA(size, coyote::DEF_PORT+3);
    if (!mem4) { throw std::runtime_error("Could not allocate memory for thread 4; exiting..."); }

    std::cout << "fourth client connected\n" << std::flush;

    std::cout << "server waiting on client writes\n" << std::flush;
    // Benchmark sweep; exactly like done in the client code
    HEADER("RDMA BENCHMARK: SERVER");
    coyote::rdmaSg sg = { .len = size };
    run_4_to_1_server(
        coyote_thread_1,
        coyote_thread_2,
        coyote_thread_3,
        coyote_thread_4,
        sg,
        mem1,
        mem2,
        mem3,
        mem4,
        n_runs
    );
    // Final sync and exit
    std::cout << "server finished\n" << std::flush;
    return EXIT_SUCCESS;
}