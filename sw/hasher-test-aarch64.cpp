#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
#include <unistd.h>
#include <time.h>
#include "sha.h"
#include <fcntl.h>
#include <sys/mman.h>

#include <time.h>

#define TIME_BLOCK_MS(result_var, block)                                         \
    double result_var;                                                           \
        struct timespec __start, __end;                                          \
        clock_gettime(CLOCK_MONOTONIC, &__start);                                \
        block                                                                    \
        clock_gettime(CLOCK_MONOTONIC, &__end);                                  \
        result_var = ((double)(__end.tv_sec - __start.tv_sec) * 1000.0) +        \
                     ((double)(__end.tv_nsec - __start.tv_nsec) / 1000000.0);    

typedef struct {
    void *virtual_addr;
    unsigned long physical_addr;
	uint32_t size;
} BufferInfo;

BufferInfo map_udmabuf(size_t requested_size) {
	// bypass   parameter
	requested_size = 512*1024;
    BufferInfo info = { .virtual_addr = NULL, .physical_addr = 0, .size = requested_size};

    const char *device_path = "/dev/udmabuf0";
    const char *phys_addr_path = "/sys/class/u-dma-buf/udmabuf0/phys_addr";
    const char *size_path = "/sys/class/u-dma-buf/udmabuf0/size";

    // Read the actual size of the udmabuf0
    FILE *size_fp = fopen(size_path, "r");
    if (!size_fp) {
        perror("fopen size");
        return info;
    }

    unsigned long actual_size = 0;
    if (fscanf(size_fp, "%lu", &actual_size) != 1) {
        fprintf(stderr, "Failed to read udmabuf size\n");
        fclose(size_fp);
        return info;
    }
    fclose(size_fp);

    if (requested_size > actual_size) {
        fprintf(stderr, "Requested size (0x%zx) exceeds udmabuf0 size (0x%lx)\n",
                requested_size, actual_size);
        return info;
    }

    int fd = open(device_path, O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("open");
        return info;
    }

    void *buf = mmap(NULL, requested_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (buf == MAP_FAILED) {
        perror("mmap");
        close(fd);
        return info;
    }

    FILE *phys_fp = fopen(phys_addr_path, "r");
    if (!phys_fp) {
        perror("fopen phys_addr");
        munmap(buf, requested_size);
        close(fd);
        return info;
    }

    unsigned long phys_addr = 0;
    if (fscanf(phys_fp, "%lx", &phys_addr) != 1) {
        fprintf(stderr, "Failed to read physical address\n");
        fclose(phys_fp);
        munmap(buf, requested_size);
        close(fd);
        return info;
    }

    fclose(phys_fp);
    close(fd);

    info.virtual_addr = buf;
    info.physical_addr = phys_addr;
    return info;
}


// Structure used to pass commands between user-space and kernel-space.
struct user_message {
    uint32_t block_address_base;
    uint32_t n_blocks;
    uint32_t difficulty;
    uint32_t result_address;
};


// Base address for the mapping of (all) peripherals
#define BASE_MAP  0xA0000000

#define DEFAULT_MAX_BLOCKS 16
#define DEFAULT_N_EXPERIMENTS 5 
#define DEFAULT_MAX_DIFFICULTY 16 

#define FUNC_TESTING 0
#define DEBUG 0
#define DUMP 0
#define ACCELERATOR 1

const char* DRIVER_NAME="/dev/hasher";
int driver;

struct experiment_stats
{
    double time_taken_ms;
    uint64_t hash_per_sec;
};

uint64_t _bswap64(uint64_t val)
{
    uint64_t res = 0;
    res |= ((val & 0xff) << 56);
    res |= ((val & 0xff00) << 40);
    res |= ((val & 0xff0000) << 24);
    res |= ((val & 0xff000000) << 8);
    res |= ((val & 0xff00000000) >> 8);
    res |= ((val & 0xff0000000000) >> 24);
    res |= ((val & 0xff000000000000) >> 40);
    res |= ((val & 0xff00000000000000) >> 56);
    return res;
}

uint32_t _bswap32(uint32_t val)
{
    uint32_t res = 0;
    res |= ((val & 0xff) << 24);
    res |= ((val & 0xff00) << 8);
    res |= ((val & 0xff0000) >> 8);
    res |= ((val & 0xff000000) >> 24);
    return res;
}

struct hasher_result
{
    uint32_t b;
    uint32_t a;
    uint32_t d;
    uint32_t c;
    uint32_t nonce;
    uint32_t e;
}__attribute((packed))__;


uint64_t compute_avg_hash_per_second(uint8_t *addr, uint32_t n_blocks, double time_taken_ms)
{
    uint64_t total_nonces = 0;
    for(uint32_t i = 0; i < n_blocks; ++i)
    {
        struct hasher_result res = *((struct hasher_result*)(addr + 24*i));
        total_nonces += res.nonce;
    }

    return (double)total_nonces * 1000 / time_taken_ms;
}

void print_memory_bytes(uint8_t* arr, uint32_t count)
{
    for(uint32_t i = 0; i < count; ++i)
    {
        printf("%02x", arr[i]);
        if((i + 1) % 64 == 0)printf("\n");
    }
    printf("\n");
}

void print_hash_nonces(uint32_t* start_addr, uint8_t block_count)
{
    for(uint32_t b = 0; b < block_count; ++b)
    {
        printf("BLOCK: %u\n", b);
        printf("\tHASH: ");
        struct hasher_result res = *(struct hasher_result*)((uint8_t*)start_addr +24*b);
        printf("%08x%08x%08x%08x%08x",res.a, res.b, res.c, res.d, res.e);
        printf("\tNONCE: %08x\n", res.nonce);
    }
}

void test_device()
{

    uint32_t n_blocks = 2;
    uint32_t difficulty = 0xFFFFF000;

	BufferInfo buf = map_udmabuf(1024);

    uint32_t * virtual_addr = (uint32_t*)buf.virtual_addr;
    if(!virtual_addr)
    {
        printf("Error cma_alloc\n"); 
        exit(-1);
    }

    uint32_t *physical_addr = (uint32_t *)buf.physical_addr;
    printf("Physical Addr: %x\n", (uint64_t)physical_addr);


    uint64_t *start_address = (uint64_t*)virtual_addr;
    uint64_t val;
    for(uint32_t i = 0; i < n_blocks; ++i)
    {
        if (i == 0)
            val = 0xFFFFFFFFFFFFFFFF;
        else
            val = 0x0F0F0F0F0F0F0F0F;
        for(uint32_t j = 0; j < 8; ++j)
        {
            *(start_address + i * 8 + j) = val; 
        }

    }

    print_memory_bytes((uint8_t*)start_address, 64 * n_blocks);



    struct user_message mex = {(uint64_t)physical_addr, n_blocks, difficulty, (uint64_t)((uint8_t*)physical_addr + 64*n_blocks + 64)};

    TIME_BLOCK_MS(msec, uint32_t driver_err = read(driver, (void*)&mex, sizeof(mex));)
    if(driver_err)
    {
        printf("Invalid read from driver\n");
        exit(-1);
    }

    printf("\nDONE EXPERIMENT\n");
    printf("Time: %f (ms)", msec);
    print_hash_nonces((uint32_t*)((uint8_t*)virtual_addr + 64*n_blocks + 64), n_blocks);


    munmap(buf.virtual_addr, buf.size);

}


struct experiment_stats run_experiment(uint32_t n_blocks, uint32_t difficulty)
{

    struct experiment_stats res;
#if DEBUG
    printf("-----------------------------------------------\n\n");
#endif
    BufferInfo buf = map_udmabuf(n_blocks * 64 + n_blocks * 24 + 1024);
    uint32_t * virtual_addr = (uint32_t *) buf.virtual_addr;
    if(!virtual_addr)
    {
        printf("Error cma_alloc\n"); 
        exit(-1);
    }

    uint32_t *physical_addr = (uint32_t *)buf.physical_addr;
#if DEBUG
    printf("Physical Addr: %x\n", (uint64_t)physical_addr);
#endif


    uint64_t *start_address = (uint64_t*)virtual_addr;
    for(uint32_t i = 0; i < n_blocks; ++i)
    {
        for(uint32_t j = 0; j < 8; ++j)
        {
            *(start_address + i * 8 + j) = rand(); 
        }

    }

#if DEBUG
    print_memory_bytes((uint8_t*)start_address, 64);
#endif

    struct user_message mex = {(uint64_t)physical_addr, n_blocks, difficulty, (uint64_t)((uint8_t*)physical_addr + 64*n_blocks + 64)};

    TIME_BLOCK_MS(msec, uint32_t driver_err = read(driver, (void*)&mex, sizeof(mex));)
    if(driver_err)
    {
        printf("Invalid read from driver\n");
        exit(-1);
    }

#if DEBUG
    printf("\nDONE EXPERIMENT\n");
    printf("Time: %f (ms)", msec);
    print_hash_nonces((uint32_t*)((uint8_t*)virtual_addr + n_blocks * 64 + 64), n_blocks);
#endif

    res.time_taken_ms = msec;
    res.hash_per_sec = compute_avg_hash_per_second((uint8_t*)virtual_addr + n_blocks * 64 + 64, n_blocks, msec);

    munmap(buf.virtual_addr, buf.size);
    return res;
}

struct hasher_result compute_hash_block_cpu(uint8_t* addr, uint32_t difficulty)
{
    uint32_t nonce = 0;
    struct hasher_result final_result;
    while(1)
    {
        *(uint32_t*)(addr + 60) = nonce;
        struct internal_state res = sha1(addr, 64);
        if(!(res.A & difficulty))
        {
            //Nonce found
            final_result.a = res.A;
            final_result.b = res.B;
            final_result.c = res.C;
            final_result.d = res.D;
            final_result.e = res.E;
            final_result.nonce = nonce;
            break;
        }
        nonce += 1;
    }
    return final_result;
}


struct experiment_stats run_experiment_cpu(uint32_t n_blocks, uint32_t difficulty)
{

    struct experiment_stats res;
#if DEBUG
    printf("-----------------------------------------------\n\n");
#endif
	BufferInfo buf = map_udmabuf(n_blocks * 64 + n_blocks * 24 + 1024);

    uint32_t * virtual_addr = (uint32_t*)buf.virtual_addr;
    if(!virtual_addr)
    {
        printf("Error cma_alloc\n"); 
        exit(-1);
    }

    uint64_t *start_address = (uint64_t*)virtual_addr;
    for(uint32_t i = 0; i < n_blocks; ++i)
    {
        for(uint32_t j = 0; j < 8; ++j)
        {
            *(start_address + i * 8 + j) = rand(); 
        }

    }

#if DEBUG
    print_memory_bytes((uint8_t*)start_address, 64);
#endif


    clock_t diff = 0;
    uint32_t tot_nonces = 0;
    clock_t start = clock();

    for(uint32_t i = 0; i < n_blocks; ++i)
    {
        start = clock();
        struct hasher_result res = compute_hash_block_cpu((uint8_t*)start_address + 64*i, difficulty);
        diff += (clock() - start);
        tot_nonces += res.nonce;
    }


    double msec = ((double)diff / CLOCKS_PER_SEC) * 1000;
#if DEBUG
    printf("\nDONE EXPERIMENT\n");
    printf("Time: %f (ms)", msec);
#endif

    res.time_taken_ms = msec;
    res.hash_per_sec = (double)tot_nonces * 1000 / msec;

    munmap(buf.virtual_addr, buf.size);
    return res;
}

int main(int argc, char **argv)
{
    driver = open(DRIVER_NAME, O_RDWR);
    if (driver == -1)
    {
        printf("Error opening the driver\n");
        exit(-1);
    }

    // If "test" is passed as the first argument, run test_device
    if (argc >= 2 && strcmp(argv[1], "test") == 0)
    {
        test_device();
        close(driver);
        return 0;
    }

    // Argument parsing
    uint32_t MAX_BLOCKS;
    uint32_t N_EXPERIMENTS;
    uint32_t MAX_DIFFICULTY;

    if (argc == 1)
    {
        MAX_BLOCKS = DEFAULT_MAX_BLOCKS;
        N_EXPERIMENTS = DEFAULT_N_EXPERIMENTS;
        MAX_DIFFICULTY = DEFAULT_MAX_DIFFICULTY;
    }
    else if (argc == 4)
    {
        MAX_BLOCKS = atoi(argv[1]);
        N_EXPERIMENTS = atoi(argv[2]);
        MAX_DIFFICULTY = atoi(argv[3]);
    }
    else
    {
        printf("usage: ./master [test] OR ./master max_blocks experiments max_difficulty\n");
        exit(-1);
    }

    printf("----------------------------\n");
    printf("Press ENTER to start experiments\n");
    getchar();

    if (MAX_DIFFICULTY > 32)
    {
        printf("Invalid difficulty selected\n");
        exit(-1);
    }

    // Consistent experiments
    srand(12);

    struct experiment_stats stats_accel;
    struct experiment_stats stats_cpu;
    double temp = 0.0;

    printf("[\n");
    for (uint32_t d = 16; d <= MAX_DIFFICULTY; d += 4)
    {
        uint32_t difficulty = 0xFFFFFFFF & (0xFFFFFFFF << (32 - d));
        printf("{\n");
        printf("\"DIFFICULTY\": \"%08x\",\n", difficulty);
        printf("\"BLOCK_EXPERIMENTS\": [\n");

        for (uint32_t i = 1; i < MAX_BLOCKS; ++i)
        {
            double avg_time_accel = 0.0, max_time_accel = 0.0, min_time_accel = 1e8, hash_per_sec_accel = 0.0;
            double avg_time_cpu = 0.0, max_time_cpu = 0.0, min_time_cpu = 1e8, hash_per_sec_cpu = 0.0;

            for (uint32_t j = 0; j < N_EXPERIMENTS; ++j)
            {
                stats_accel = run_experiment(i, difficulty);
                temp = stats_accel.time_taken_ms;
                if (temp > max_time_accel) max_time_accel = temp;
                if (temp < min_time_accel) min_time_accel = temp;
                avg_time_accel += temp;
                hash_per_sec_accel += stats_accel.hash_per_sec;

                stats_cpu = run_experiment_cpu(i, difficulty);
                temp = stats_cpu.time_taken_ms;
                if (temp > max_time_cpu) max_time_cpu = temp;
                if (temp < min_time_cpu) min_time_cpu = temp;
                avg_time_cpu += temp;
                hash_per_sec_cpu += stats_cpu.hash_per_sec;
            }

            printf("{\"Blocks\": %u,\n", i);
            printf("\"Accelerator\": {\"min_time\": %f, \"max_time\": %f, \"avg_time\": %f, \"avg_hash_per_sec\": %f},\n",
                   min_time_accel, max_time_accel, avg_time_accel / N_EXPERIMENTS, hash_per_sec_accel / N_EXPERIMENTS);
            printf("\"CPU\": {\"min_time\": %f, \"max_time\": %f, \"avg_time\": %f, \"avg_hash_per_sec\": %f}\n",
                   min_time_cpu, max_time_cpu, avg_time_cpu / N_EXPERIMENTS, hash_per_sec_cpu / N_EXPERIMENTS);
            printf("}");
            if (i != MAX_BLOCKS - 1)
                printf(",\n");
        }

        printf("]\n");
        printf("}");
        if (d != MAX_DIFFICULTY)
            printf(",\n");
    }
    printf("]\n");

    close(driver);
    return 0;
}


