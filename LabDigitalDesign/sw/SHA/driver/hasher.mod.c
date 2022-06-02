#include <linux/build-salt.h>
#include <linux/module.h>
#include <linux/vermagic.h>
#include <linux/compiler.h>

BUILD_SALT;

MODULE_INFO(vermagic, VERMAGIC_STRING);
MODULE_INFO(name, KBUILD_MODNAME);

__visible struct module __this_module
__section(.gnu.linkonce.this_module) = {
	.name = KBUILD_MODNAME,
	.init = init_module,
#ifdef CONFIG_MODULE_UNLOAD
	.exit = cleanup_module,
#endif
	.arch = MODULE_ARCH_INIT,
};

#ifdef CONFIG_RETPOLINE
MODULE_INFO(retpoline, "Y");
#endif

static const struct modversion_info ____versions[]
__used __section(__versions) = {
	{ 0x136a4a24, "module_layout" },
	{ 0xf7c9d942, "param_ops_int" },
	{ 0x7b99d526, "cdev_add" },
	{ 0xe63cbb45, "cdev_init" },
	{ 0xe97c4103, "ioremap" },
	{ 0xae9849dd, "__request_region" },
	{ 0xe3ec2f2b, "alloc_chrdev_region" },
	{ 0xc94d8e3b, "iomem_resource" },
	{ 0x6091b333, "unregister_chrdev_region" },
	{ 0x9445c4ea, "cdev_del" },
	{ 0x4384eb42, "__release_region" },
	{ 0xedc03953, "iounmap" },
	{ 0x8f678b07, "__stack_chk_guard" },
	{ 0xae353d77, "arm_copy_from_user" },
	{ 0xdecd0b29, "__stack_chk_fail" },
	{ 0xefd6cf06, "__aeabi_unwind_cpp_pr0" },
	{ 0x822137e2, "arm_heavy_mb" },
	{ 0xc5850110, "printk" },
};

MODULE_INFO(depends, "");


MODULE_INFO(srcversion, "81E0692EE5ABB87E357B837");
