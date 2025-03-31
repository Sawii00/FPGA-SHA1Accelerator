# Hasher

Old version for Pynq board armv7 on zynq7000

# Hasher Platform

Newer version platform driver that get's automatically loaded if the overlay contains a compatible string for the accelerator. Built for aarch64 (Zynq Ultrascale+)

## Example dts

```
/dts-v1/;
/plugin/;
&fpga_full {
	firmware-name = "zusys_wrapper_sha.bit.bin";
	resets = <&zynqmp_reset 116>;
};
&amba {
	#address-cells = <2>;
	#size-cells = <2>;
	afi0: afi0 {
		compatible = "xlnx,afi-fpga";
		config-afi = < 0 0>, <1 0>, <2 0>, <3 0>, <4 1>, <5 1>, <6 0>, <7 0>, <8 0>, <9 0>, <10 0>, <11 0>, <12 0>, <13 0>, <14 0xa00>, <15 0x000>;
	};
	TopLevel_0: TopLevel@a0000000 {
		clock-names = "clk";
		clocks = <&zynqmp_clk 71>;
		compatible = "xlnx,TopLevel-1.0";
		interrupt-names = "irq";
		interrupt-parent = <&gic>;
		interrupts = <0 89 4>;
		reg = <0x0 0xa0000000 0x0 0x1000>;
		xlnx,m00-axi-addr-width = <0x20>;
		xlnx,m00-axi-data-width = <0x40>;
		xlnx,num-registers = <0x9>;
		xlnx,s00-axi-addr-width = <0x6>;
		xlnx,s00-axi-data-width = <0x20>;
	};
};


```