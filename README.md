# Clustered Hardware Implementation of an FPGA-based SHA-1 Accelerator for PoW Consensus

This was the final project for the course EE-390(a) (TP de conception de systèmes numériques) at EPFL, with the goal of becoming familiar with many aspects of hardware-software co-design on a Zynq-7000 FPGA. 

## Project Overview
The system allows the computation of SHA-1 hashes of a list of 512-bit blocks that respect a given complexity. Each cluster is composed of multiple hashers and is assigned to the hashing of one specific block. Its goal is to find a suitable nonce to be included in the block to yield a SHA-1 hash that starts with a user-specified number of leading zeros. 

Multiple configurations can be achieved based on the board's capacity. For instance, 1 cluster made of 8 hashers would compute all hashes one by one by focusing all 8 nodes on a single block until solved, and then moving onto the next. The same number of hashers could be split across 8 separate clusters, which could start one block each in parallel but clearly would only have 1 hasher working on it. The performance of such different configurations have been extracted and discussed. 

## System Overview
The main controller is programmed as an AXI4-Lite Slave and orchestrates the behavior of each cluster. When a hash is completed, the main controller writes back to memory via an AXI4-Lite Master interface. Each cluster is managed by an internal Cluster Controller, which assigns a unique nonce to the hashers and asserts the validity of the final hash. 

The whole system can be parametrically configured in terms of clusters and hashers within each cluster without extra setup required. The system automatically instantiates the required components and routes them to obtain a functioning design. 

![image](https://user-images.githubusercontent.com/23176335/178532827-eb7f6985-5117-491f-99ac-8fcaea0db774.png)

![image](https://user-images.githubusercontent.com/23176335/178532864-1cb9ebd7-9d93-4ab5-a579-c196cd9f4b15.png)

## Software
The software runs on Linux, and a custom kernel driver is provided to abstract away the hardware details and register map to the user application. 

## Performance
Despite many improvements can be made to the system design, which handles poorly the memory accesses without employing an AXI4-Full Master and only runs at 76 MHz, we are able to achieve a 40x speedup compared to a software only approach running on the ARM processor of the Pynq-Z2 (at around 600MHz)
