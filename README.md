# Bitmask-Aware Systolic Array for Edge AI Acceleration

## Overview
This repository contains the RTL implementation of a 4x4 Processing-in-Memory (PIM) systolic array prototype, written from scratch in SystemVerilog.
Designed specifically for edge AI hardware acceleration, this architecture leverages bitmasking techniques to identify and skip zero-value operands in sparse matrices. This optimization minimizes redundant switching activity, reducing dynamic power consumption and accelerating inference latency on FPGAs.

## Key Features
* **4x4 PE Architecture:** A scalable 2D grid of Processing Elements tailored for Matrix Multiplication (MAC operations).
* **Bitmask Zero-Skipping:** Custom control logic that evaluates data sparsity on the fly, dynamically gating clock signals to inactive PEs during zero-multiply operations.
* **Processing-in-Memory (PIM) Paradigm:** Architecture minimizes external memory access bottlenecks by keeping weights stationary within the PE grid during computation passes.
* **FPGA-Ready:** Fully synthesizable SystemVerilog, optimized for deployment and timing closure on Xilinx FPGAs.
