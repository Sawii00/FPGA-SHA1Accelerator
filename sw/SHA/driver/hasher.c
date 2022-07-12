#include <linux/init.h> /* needed for module_init and exit */
#include <linux/module.h>
#include <linux/moduleparam.h> /* needed for module_param */
#include <linux/kernel.h>      /* needed for printk */
#include <linux/types.h>       /* needed for dev_t type */
#include <linux/kdev_t.h>      /* needed for macros MAJOR, MINOR, MKDEV... */
#include <linux/fs.h>          /* needed for register_chrdev_region, file_operations */
#include <linux/interrupt.h>
#include <linux/cdev.h>  /* cdev definition */
#include <linux/slab.h>  /* kmalloc(),kfree() */
#include <asm/uaccess.h> /* copy_to copy_from _user */
#include <linux/uaccess.h>
#include <linux/io.h>

#define DRIVER_NAME "hash_driver"
#define HASHER_IRQ 48 // Hard-coded value of IRQ vector (GIC: 61).

#define BLOCK_ADDRESS 0
#define N_BLOCKS 1
#define DIFFICULTY 2
#define START 3
#define STOP 4
#define DONE 5
#define RESULT_ADDRESS 6

// Global enable IRQ
#define REG_ENABLE_INTERRUPTS 0x07
// Interrupt Status Register. We use only the done bit (0).
#define REG_ISR 0x08

#define DRIVER_WITH_INTERRUPT 1

// Structure used to pass commands between user-space and kernel-space.
struct user_message
{
    uint32_t block_address_base;
    uint32_t n_blocks;
    uint32_t difficulty;
    uint32_t result_address;
};

int hasher_major = 0;
int hasher_minor = 0;
module_param(hasher_major, int, S_IRUGO); // IRUGO: parameter can be read by the world but not changed
module_param(hasher_minor, int, S_IRUGO);

#if DRIVER_WITH_INTERRUPT
// We declare a wait queue that will allow us to wait on a condition.
// Waitqueues allow you to sleep until someone wakes you up.
wait_queue_head_t wq;
int flag = 0;
#endif

// This structure contains the device information.
struct hasher_info
{
    int irq;
    unsigned long memStart;
    unsigned long memEnd;
    void __iomem *baseAddr;
    struct cdev cdev; /* Char device structure               */
};

static struct hasher_info hasher_mem = {HASHER_IRQ, 0x43C00000, 0x43C0FFFF};

// Declare here the user-accessible functions that the driver implements.
int hasher_open(struct inode *inode, struct file *filp);
int hasher_release(struct inode *inode, struct file *filed_mem);
ssize_t hasher_read(struct file *filed_mem, char __user *buf, size_t count, loff_t *f_pos);

#if DRIVER_WITH_INTERRUPT
// IRQ handler function.
static irq_handler_t hasherIRQHandler(unsigned int irq, void *dev_id, struct pt_regs *regs);
#endif

// This structure declares the operations that our driver exports for the users.
struct file_operations hasher_fops = {
    .owner = THIS_MODULE,
    .read = hasher_read,
    .open = hasher_open,
    .release = hasher_release,
};

// Function that implements system call open() for our driver.
// Initialize the device and enable the interrups here.
int hasher_open(struct inode *inode, struct file *filp)
{
    pr_info("hasher_DRIVER: Performing 'open' operation\n");
#if DRIVER_WITH_INTERRUPT
    iowrite32(0xFFFFFFFF, hasher_mem.baseAddr + sizeof(uint32_t) * REG_ENABLE_INTERRUPTS);
    iowrite32(0x1, hasher_mem.baseAddr + sizeof(uint32_t) * REG_ISR);
#endif

    mb();
    return 0;
}

// Function that implements system call release() for our driver.
// Used with close() or when the OS closes the descriptors held by
// the process when it is closed (e.g., Ctrl-C).
// Stop the interrupts and disable the device.
int hasher_release(struct inode *inode, struct file *filed_mem)
{
    pr_info("hasher_DRIVER: Performing 'release' operation\n");

#if DRIVER_WITH_INTERRUPT
    iowrite32(0, hasher_mem.baseAddr + sizeof(uint32_t) * REG_ENABLE_INTERRUPTS);
    iowrite32(1, hasher_mem.baseAddr + sizeof(uint32_t) * REG_ISR);
#endif

    mb();
    return 0;
}

// The cleanup function is used to handle initialization failures as well.
// Thefore, it must be careful to work correctly even if some of the items
// have not been initialized

void hasher_cleanup_module(void)
{
    dev_t devno = MKDEV(hasher_major, hasher_minor); // Combines major and minor number in dev_t (32 bit) by concatenating
#if DRIVER_WITH_INTERRUPT
    disable_irq(hasher_mem.irq);
    free_irq(hasher_mem.irq, &hasher_mem);
#endif
    iounmap(hasher_mem.baseAddr);
    release_mem_region(hasher_mem.memStart, hasher_mem.memEnd - hasher_mem.memStart + 1);
    cdev_del(&hasher_mem.cdev);
    unregister_chrdev_region(devno, 1); /* unregistering device */
    pr_info("hasher_DRIVER: Cdev deleted, hasher device unmapped, chdev unregistered\n");
}

// Function that implements system call read() for our driver.
// Returns 1 uint32_t with the number of times the interrupt has been detected.
ssize_t hasher_read(struct file *filed_mem, char __user *buf, size_t count, loff_t *f_pos)
{
    struct user_message message;
    uint32_t status;

    if (count < sizeof(struct user_message))
    {
        pr_err("hasher_DRIVER: USer buffer too small (> %d bytes).\n", sizeof(struct user_message));
        return -1;
    }

    // Copy the information from user-space to the kernel-space buffer.
    if (raw_copy_from_user(&message, buf, sizeof(struct user_message)))
    {
        pr_err("hasher_DRIVER: Raw copy from user buffer failed.\n");
        return -1;
    }

    // Program the peripheral registers.
    iowrite32(message.block_address_base, hasher_mem.baseAddr + BLOCK_ADDRESS * sizeof(uint32_t));
    iowrite32(message.n_blocks, hasher_mem.baseAddr + N_BLOCKS * sizeof(uint32_t));
    iowrite32(message.difficulty, hasher_mem.baseAddr + DIFFICULTY * sizeof(uint32_t));
    iowrite32(message.result_address, hasher_mem.baseAddr + RESULT_ADDRESS * sizeof(uint32_t));
#if DRIVER_WITH_INTERRUPT
    iowrite32(0xFFFFFFFF, hasher_mem.baseAddr + sizeof(uint32_t) * REG_ENABLE_INTERRUPTS);
    iowrite32(0x1, hasher_mem.baseAddr + sizeof(uint32_t) * REG_ISR);
    mb();
#endif

    iowrite32(1, hasher_mem.baseAddr + START * sizeof(uint32_t));
    mb();
    iowrite32(0, hasher_mem.baseAddr + START * sizeof(uint32_t));
    mb();
    pr_info("hasher_DRIVER: Starting accel...\n");

    // Sleep the thread until the peripheral generates an interrupt
    // wait_event_interruptible may exit when a signal is received, so
    // we check our flag to ensure that it was our own interrupt handler
    // waking up us after the interrupt is received, and not an
    // spurious signal.
    // When we go to sleep, the processor is free for other tasks.
#if DRIVER_WITH_INTERRUPT
    // printk("Val: %x\n", ioread32(hasher_mem.baseAddr + sizeof(uint32_t) * REG_ENABLE_INTERRUPTS));
    flag = 0;
    while (wait_event_interruptible(wq, flag != 0))
    {
        printk(KERN_ALERT "hasher_DRIVER: AWOKEN BY ANOTHER SIGNAL\n");
    }
    pr_info("hasher_DRIVER: AWOKEN FROM INTERRUPT\n");

    // Disable interrupts.
    // iowrite32(0, hasher_mem.baseAddr + sizeof(uint32_t) * REG_ENABLE_INTERRUPTS);
#else
    // INSERT POLLING HERE
    while (!ioread32(hasher_mem.baseAddr + DONE * sizeof(uint32_t)))
        ;
#endif

    pr_info("hasher_DRIVER: Performed READ operation successfully\n");
    return 0;
}

// Set up the char_dev structure for this device.
static void hasher_setup_cdev(struct hasher_info *_hasher_mem)
{
    int err, devno = MKDEV(hasher_major, hasher_minor);

    cdev_init(&_hasher_mem->cdev, &hasher_fops);
    _hasher_mem->cdev.owner = THIS_MODULE;
    _hasher_mem->cdev.ops = &hasher_fops;
    err = cdev_add(&_hasher_mem->cdev, devno, 1);
    /* Fail gracefully if need be */
    if (err)
        pr_err("hasher_DRIVER: Error %d adding hasher cdev_add", err);

    pr_info("hasher_DRIVER: Cdev initialized\n");
}

// The init function registers the chdev.
// It allocates dynamically a new major number.
// The major number corresponds to a different function driver.
static int hasher_init(void)
{
    int result = 0;
    dev_t dev = 0;

    // Allocate a function number for our driver (major number).
    // The minor number is the instance of the driver.
    pr_info("hasher_DRIVER: Allocating a new major number.\n");
    result = alloc_chrdev_region(&dev, hasher_minor, 1, "hasher"); // Registers a range of char device numbers
    hasher_major = MAJOR(dev);                                     // Extracts the major from the dev_t (upper 12 bits are major)
    if (result < 0)
    {
        pr_err("hasher_DRIVER: Can't get major %d\n", hasher_major);
        return result;
    }

    // Request (exclusive) access to the memory address range of the peripheral.
    if (!request_mem_region(hasher_mem.memStart, hasher_mem.memEnd - hasher_mem.memStart + 1, DRIVER_NAME))
    {
        pr_err("hasher_DRIVER: Couldn't lock memory region at %p\n", (void *)hasher_mem.memStart);
        unregister_chrdev_region(dev, 1);
        return -1;
    }

    // Obtain a "kernel virtual address" for the physical address of the peripheral.
    hasher_mem.baseAddr = ioremap(hasher_mem.memStart, hasher_mem.memEnd - hasher_mem.memStart + 1);
    if (!hasher_mem.baseAddr)
    {
        pr_err("hasher_DRIVER: Could not obtain virtual kernel address for iomem space.\n");
        release_mem_region(hasher_mem.memStart, hasher_mem.memEnd - hasher_mem.memStart + 1);
        unregister_chrdev_region(dev, 1);
        return -1;
    }

#if DRIVER_WITH_INTERRUPT
    init_waitqueue_head(&wq);

    // Request registering our interrupt handler for the IRQ of the peripheral.
    // We configure the interrupt to be detected on the rising edge of the signal.
    result = request_irq(hasher_mem.irq, (irq_handler_t)hasherIRQHandler, IRQF_TRIGGER_RISING, DRIVER_NAME, &hasher_mem);
    if (result)
    {
        printk(KERN_ALERT "hasher_DRIVER: Failed to register interrupt handler (error=%d)\n", result);
        iounmap(hasher_mem.baseAddr);
        release_mem_region(hasher_mem.memStart, hasher_mem.memEnd - hasher_mem.memStart + 1);
        cdev_del(&hasher_mem.cdev);
        unregister_chrdev_region(dev, 1);
        return result;
    }

    // Enable the IRQ. From this moment on, we can receive the IRQ asynchronously at any time.
    enable_irq(hasher_mem.irq);
    pr_info("hasher_DRIVER: Interrupt %d registered\n", hasher_mem.irq);
#endif

    pr_info("hasher_DRIVER: driver at 0x%08X mapped to 0x%08X\n",
            (uint32_t)hasher_mem.memStart, (uint32_t)hasher_mem.baseAddr);
    hasher_setup_cdev(&hasher_mem);

    return 0;
}

// The exit function calls the cleanup
static void hasher_exit(void)
{
    pr_info("hasher_DRIVER: calling cleanup function.\n");
    hasher_cleanup_module();
}

// Declare init and exit handlers.
// They are invoked when the driver is loaded or unloaded.
module_init(hasher_init);
module_exit(hasher_exit);

#if DRIVER_WITH_INTERRUPT
// The interrupt handler is called on the (rising edge of the) accelerator interrupt.
// The interrupt handler is executed in an interrupt context, not a process context!!!
// It must be quick, it cannot sleep. It cannot use functions that can sleep
// (e.g., don't allocate memory if that may wait for swapping).
// The handler cannot communicate directly with the user-space. The user-space does not
// interact with the interrupt handler.
static irq_handler_t hasherIRQHandler(unsigned int irq, void *dev_id, struct pt_regs *regs)
{
    if (irq != HASHER_IRQ)
        return IRQ_NONE;
    // Clean the interrupt in the peripheral, so that we can detect new rising transition.
    // The ISR is toggle-on-write (TOW), which means that its bits toggle when they are
    // written, whatever it was their previous value. Therefore, we write (1) to the
    // 'done' bit to toggle it, so that it becomes 0 and the interrupt is disarmed.
    iowrite32(1, hasher_mem.baseAddr + sizeof(uint32_t) * REG_ISR);
    mb();
    // Signal that it is us waking the main thread.
    flag = 1;
    // Wake the main thread.
    wake_up_interruptible(&wq);
    return (irq_handler_t)IRQ_HANDLED; // Announce that the IRQ has been handled correctly
    // In case of error, or if it was not our device which generated the IRQ, return IRQ_NONE.
}
#endif

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Saverio Nasturzio - Gianluca Radi");
MODULE_DESCRIPTION("Driver for SHA1 Hasher");
MODULE_VERSION("1.0");
