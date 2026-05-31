#include "rocc.h"
#include <stdint.h>
#include <stdio.h>

#define NTT_FUNCT_START 0
#define NTT_FUNCT_LOAD_A 1
#define NTT_FUNCT_LOAD_B 2
#define NTT_FUNCT_READ 3
#define NTT_FUNCT_STATUS 4
#define NTT_FUNCT_DEBUG_READ_A 5
#define NTT_FUNCT_DEBUG_READ_B 6

#define NTT_STATUS_DONE 0x1
#define NTT_STATUS_BUSY 0x2
#define NTT_STATUS_FWD_DONE 0x100
#define NTT_STATUS_INV_DONE 0x200
#define NTT_STATUS_FWD_STARTED 0x400
#define NTT_STATUS_INV_STARTED 0x800

#define NTT_STATE_DONE 10
#define NTT_N 4096

static inline void ntt_load_a(uint64_t addr, uint64_t data)
{
	ROCC_INSTRUCTION_SS(0, addr, data, NTT_FUNCT_LOAD_A);
}

static inline void ntt_load_b(uint64_t addr, uint64_t data)
{
	ROCC_INSTRUCTION_SS(0, addr, data, NTT_FUNCT_LOAD_B);
}

static inline void ntt_start(void)
{
	ROCC_INSTRUCTION(0, NTT_FUNCT_START);
}

static inline uint64_t ntt_read(uint64_t addr)
{
	uint64_t value;
	ROCC_INSTRUCTION_DSS(0, value, addr, 0, NTT_FUNCT_READ);
	return value;
}

static inline uint64_t ntt_debug_read_a(uint64_t addr)
{
	uint64_t value;
	ROCC_INSTRUCTION_DS(0, value, addr, NTT_FUNCT_DEBUG_READ_A);
	return value;
}

static inline uint64_t ntt_debug_read_b(uint64_t addr)
{
	uint64_t value;
	ROCC_INSTRUCTION_DS(0, value, addr, NTT_FUNCT_DEBUG_READ_B);
	return value;
}

static inline uint64_t ntt_status(void)
{
	uint64_t value;
	ROCC_INSTRUCTION_D(0, value, NTT_FUNCT_STATUS);
	return value;
}

static inline uint32_t ntt_debug_state(uint64_t status)
{
	return (uint32_t)((status >> 4) & 0xf);
}

static inline void ntt_print_status(uint64_t status)
{
	printf("ntt status=0x%lx state=%u fwd_done=%u inv_done=%u fwd_started=%u inv_started=%u\n",
		status,
		ntt_debug_state(status),
		(status & NTT_STATUS_FWD_DONE) ? 1 : 0,
		(status & NTT_STATUS_INV_DONE) ? 1 : 0,
		(status & NTT_STATUS_FWD_STARTED) ? 1 : 0,
		(status & NTT_STATUS_INV_STARTED) ? 1 : 0);
}

static uint32_t mod_q(int64_t value)
{
	const int64_t q = 8380417;
	int64_t res = value % q;
	if (res < 0)
		res += q;
	return (uint32_t)res;
}

int main(void)
{
	static uint32_t poly_a[NTT_N] = {0};
	static uint32_t poly_b[NTT_N] = {0};
	static uint32_t expected[NTT_N] = {0};
	static uint32_t got[NTT_N] = {0};

	poly_a[0] = 1;
	poly_a[1] = 2;
	poly_a[2] = 3;
	poly_b[0] = 5;
	poly_b[1] = 1;

	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 2; j++) {
			expected[i + j] = mod_q(expected[i + j] + (int64_t)poly_a[i] * poly_b[j]);
		}
	}

	for (uint32_t i = 0; i < NTT_N; i++) {
		ntt_load_a(i, poly_a[i]);
		ntt_load_b(i, poly_b[i]);
	}

	for (uint32_t i = 0; i < 4; i++) {
		uint32_t a_val = (uint32_t)ntt_debug_read_a(i);
		uint32_t b_val = (uint32_t)ntt_debug_read_b(i);
		printf("ntt load check idx=%u a=%u b=%u\n", i, a_val, b_val);
	}

	ntt_start();

	printf("ntt input a (nonzero):\n");
	for (uint32_t i = 0; i < NTT_N; i++) {
		if (poly_a[i] != 0)
			printf("  a[%u]=%u\n", i, poly_a[i]);
	}
	printf("ntt input b (nonzero):\n");
	for (uint32_t i = 0; i < NTT_N; i++) {
		if (poly_b[i] != 0)
			printf("  b[%u]=%u\n", i, poly_b[i]);
	}

	uint64_t status = ntt_status();
	uint64_t polls = 0;
	uint32_t last_state = 0xff;
	while ((status & NTT_STATUS_DONE) == 0) {
		uint32_t state = ntt_debug_state(status);
		if (state != last_state) {
			printf("ntt state=%u\n", state);
			ntt_print_status(status);
			last_state = state;
		}
		if (polls++ > 100000) {
			printf("ntt timeout\n");
			ntt_print_status(status);
			return 3;
		}
		status = ntt_status();
	}
	printf("ntt done\n");
	ntt_print_status(status);

	if (status & NTT_STATUS_BUSY)
		return 1;

	for (uint32_t i = 0; i < NTT_N; i++) {
		got[i] = (uint32_t)ntt_read(i);
	}
	printf("ntt output (first 16):\n");
	for (uint32_t i = 0; i < 16; i++) {
		printf("  out[%u]=%u expected[%u]=%u\n", i, got[i], i, expected[i]);
	}
	for (uint32_t i = 0; i < NTT_N; i++) {
		if (got[i] != expected[i]) {
			printf("ntt mismatch idx=%u got=%u expected=%u\n", i, got[i], expected[i]);
			return 2;
		}
	}

	return 0;
}
