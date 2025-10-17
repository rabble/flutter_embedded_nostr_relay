#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#define ARTI_SUCCESS 0

#define ARTI_ERROR_INIT -1

#define ARTI_ERROR_CONNECT -2

#define ARTI_ERROR_INVALID_PARAM -3

typedef struct ArtiTorClient {
  uint8_t _private[0];
} ArtiTorClient;

/**
 * Create a new Arti Tor client
 */
struct ArtiTorClient *arti_client_create(const char *config_json,
                                         const char *state_dir,
                                         const char *cache_dir);

/**
 * Bootstrap the Tor client (establish initial connections)
 */
int arti_client_bootstrap(struct ArtiTorClient *client);

/**
 * Connect to a target host through Tor
 */
uint64_t arti_client_connect(struct ArtiTorClient *client, const char *host, uint16_t port);

/**
 * Read data from a Tor connection
 */
int arti_connection_read(struct ArtiTorClient *client,
                         uint64_t conn_id,
                         uint8_t *buffer,
                         uintptr_t buffer_len);

/**
 * Write data to a Tor connection
 */
int arti_connection_write(struct ArtiTorClient *client,
                          uint64_t conn_id,
                          const uint8_t *data,
                          uintptr_t data_len);

/**
 * Close a Tor connection
 */
int arti_connection_close(struct ArtiTorClient *client, uint64_t conn_id);

/**
 * Destroy the Arti client and free resources
 */
void arti_client_destroy(struct ArtiTorClient *client);

/**
 * Get the library version
 */
const char *arti_get_version(void);
