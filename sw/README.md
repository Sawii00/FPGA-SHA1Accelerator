# Files

1. _master.cpp_: user application for the btc miner accelerator that does not need a kernel driver but directly accesses raw registers from userspace (tested only on Zynq7000 armv7)
1. *master_driver.cpp*: user application for the btc miner accelerator that uses the kernel driver to interact with the accelerator (tested and working only on Zynq7000 armv7)
1. *hasher-test-aarch64.cpp*: newer and better user application for the btc miner accelerator that uses the kernel driver to interact with the accelerator and u-dma-buf driver working on Zynq Ultrascale+