#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
#include <unistd.h>
#include "OverlayControl.h"
#include <time.h>
#include "sha.h"


extern "C"
{
#include <libxlnk_cma.h>
}
// Base address for the mapping of (all) peripherals
#define BASE_MAP  0x43C00000

#define BLOCK_ADDRESS 0
#define N_BLOCKS 1
#define DIFFICULTY 2
#define START 3
#define STOP 4
#define DONE 5
#define RESULT_ADDRESS 6

#define DEFAULT_MAX_BLOCKS 8
#define DEFAULT_N_EXPERIMENTS 10
#define DEFAULT_MAX_DIFFICULTY 16 

#define FUNC_TESTING 0
#define DEBUG 0
#define DUMP 0

struct experiment_stats
{
    double time_taken_ms;
    uint64_t hash_per_sec;
};

// Adjust the size of the mapping to cover all the peripherals, or use multiple mappings.
const uint32_t MAP_SIZE = 32*1024*1024; // 0x400_0000

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

void test_device(volatile uint32_t* SLAVE)
{

    uint32_t * virtual_addr = (uint32_t *) cma_alloc(1024, 0);
    if(!virtual_addr)
    {
        printf("Error cma_alloc\n"); 
        exit(-1);
    }

    uint32_t *physical_addr = (uint32_t *)cma_get_phy_addr(virtual_addr);
#if DEBUG
    printf("Physical Addr: %x\n", (uint32_t)physical_addr);
#endif


    uint64_t *start_address = (uint64_t*)virtual_addr;
    uint64_t val;
    for(uint32_t i = 0; i < 2; ++i)
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

#if DEBUG
    print_memory_bytes((uint8_t*)start_address, 128);
#endif

    *(SLAVE + BLOCK_ADDRESS) = (uint32_t)physical_addr;
    *(SLAVE + N_BLOCKS) = 2;
    *(SLAVE + START) = 0;
    *(SLAVE + STOP) = 1;
    for(volatile uint32_t i = 0; i < 1000; ++i);
    *(SLAVE + STOP) = 0;
    *(SLAVE + DIFFICULTY) = 0xFFFFF000;
    *(SLAVE + RESULT_ADDRESS) = (uint32_t)((uint8_t*)physical_addr + 512);

    clock_t diff;
    clock_t start = clock();

    *(SLAVE + START) = 0x1;
    *(SLAVE + START) = 0x0;


    while(!(*(SLAVE + DONE))){}

    diff = clock() - start;

    double msec = ((double)diff / CLOCKS_PER_SEC) * 1000;
#if DEBUG
    printf("\nDONE EXPERIMENT\n");
    printf("Time: %f (ms)", msec);
    print_hash_nonces((uint32_t*)((uint8_t*)virtual_addr +512), 2);
#endif


    cma_free(virtual_addr);

}


struct experiment_stats run_experiment(volatile uint32_t* SLAVE, uint32_t n_blocks, uint32_t difficulty)
{
    // To make all experiments the same
    srand(30);
    struct experiment_stats res;
#if DEBUG
    printf("-----------------------------------------------\n\n");
#endif
    uint32_t * virtual_addr = (uint32_t *) cma_alloc(n_blocks * 64 + n_blocks * 24 + 1024, 0);
    if(!virtual_addr)
    {
        printf("Error cma_alloc\n"); 
        exit(-1);
    }

    uint32_t *physical_addr = (uint32_t *)cma_get_phy_addr(virtual_addr);
#if DEBUG
    printf("Physical Addr: %x\n", (uint32_t)physical_addr);
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

    *(SLAVE + BLOCK_ADDRESS) = (uint32_t)physical_addr;
    *(SLAVE + N_BLOCKS) = n_blocks;
    *(SLAVE + START) = 0;
    *(SLAVE + STOP) = 1;
    for(volatile uint32_t i = 0; i < 1000; ++i);
    *(SLAVE + STOP) = 0;
    *(SLAVE + DIFFICULTY) = difficulty;
    *(SLAVE + RESULT_ADDRESS) = (uint32_t)((uint8_t*)physical_addr + n_blocks * 64 + 64);

    clock_t diff;
    clock_t start = clock();

    *(SLAVE + START) = 0x1;
    *(SLAVE + START) = 0x0;


    while(!(*(SLAVE + DONE))){}

    diff = clock() - start;

    double msec = ((double)diff / CLOCKS_PER_SEC) * 1000;
#if DEBUG
    printf("\nDONE EXPERIMENT\n");
    printf("Time: %f (ms)", msec);
    print_hash_nonces((uint32_t*)((uint8_t*)virtual_addr + n_blocks * 64 + 64), n_blocks);
#endif

    res.time_taken_ms = msec;
    res.hash_per_sec = compute_avg_hash_per_second((uint8_t*)virtual_addr + n_blocks * 64 + 64, n_blocks, msec);

    cma_free(virtual_addr);
    return res;
}



int main(int argc, char ** argv)
{
#if DUMP
    freopen("log.txt", "w", stdout);
#endif

    uint32_t MAX_BLOCKS;
    uint32_t N_EXPERIMENTS;
    uint32_t MAX_DIFFICULTY;

    if (argc == 1)
    {
        MAX_BLOCKS = DEFAULT_MAX_BLOCKS;
        N_EXPERIMENTS = DEFAULT_N_EXPERIMENTS;
        MAX_DIFFICULTY = DEFAULT_MAX_DIFFICULTY;
    }
    else if(argc == 4)
    {
        MAX_BLOCKS = atoi(argv[1]);
        N_EXPERIMENTS = atoi(argv[2]);
        MAX_DIFFICULTY = atoi(argv[3]);
    }
    else
    {
        printf("usage: ./master max_blocks experiments max_difficulty\n");
        exit(-1);
    }

    volatile uint8_t * device = NULL;
    volatile uint32_t * SLAVE;

#if not DUMP
    printf("\n\nThis program requires that the GPIO buttons and LEDs bitstream is loaded in the FPGA.\n");
    printf("This program has to be run with sudo.\n");
    printf("Press ENTER to confirm that the bitstream is loaded (proceeding without it can crash the board).\n\n");
#endif
    getchar();

    // Obtain a pointer to access the peripherals in the address map.
    device = (uint8_t*) MapMemIO(BASE_MAP, MAP_SIZE);
    if (device == NULL) {
        printf("Error opening device!\n");
        exit(-1);
    }
#if not DUMP
    printf("Mmap done. Peripherals at %08X\n", (uint32_t)device);
#endif

    SLAVE = (uint32_t*)(device);

#if not DUMP
    printf("----------------------------");
    printf("Press ENTER to start experiments\n");
#endif
    getchar();

#if FUNC_TESTING == 0

    struct experiment_stats stats;
    double temp = 0.0;

    if(MAX_DIFFICULTY > 32)
    {
        printf("Invalid difficulty selected\n");
        exit(-1);
    }

    printf("[\n");
    for(uint32_t d = 4; d <= MAX_DIFFICULTY; d += 4)
    {
        uint32_t difficulty = 0xFFFFFFFF & (0xFFFFFFFF << (32 - d));
        printf("{\n");
        printf("\"DIFFICULTY\": \"%08x\",\n", difficulty);
        printf("\"BLOCK_EXPERIMENTS\": [\n");
        for(uint32_t i = 1; i < MAX_BLOCKS; ++i)
        {
            double avg = 0.0;
            double max = 0.0;
            double min = 100000000.0;
            double hash_per_sec = 0;
            for(uint32_t j = 0; j < N_EXPERIMENTS; ++j)
            {
                stats = run_experiment(SLAVE, i, difficulty);
                temp = stats.time_taken_ms;
                if(temp > max)max = temp;
                else if (temp < min)min=temp;
                avg += temp;
                hash_per_sec += stats.hash_per_sec;
            }
            printf("{\"Blocks\": %u, \"min_time\": %f, \"max_time\": %f, \"avg_time\": %f, \"avg_hash_per_sec\": %f}", i, min, max, avg / N_EXPERIMENTS, hash_per_sec / N_EXPERIMENTS);
            if(i != MAX_BLOCKS - 1)
                printf(",\n");
        }
        printf("]\n");
        printf("}");
        //IF WE CHANGE INCREMENT VALUE REMEMBER TO CHANGE THIS TOO
        if(d != MAX_DIFFICULTY)
            printf(",\n");
    }
    printf("]\n");


    //////////////////////////////////////////////  

    UnmapMemIO();
#if DUMP
    fclose(stdout);
#endif
#else
    test_device(SLAVE);
#endif

    return 0;
}

