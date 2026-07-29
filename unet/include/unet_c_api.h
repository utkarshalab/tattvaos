/* =============================================================================
 * Tattva OS — unet/include/unet_c_api.h
 * =============================================================================
 * C/C++ Userland Application Header Bindings for unet Network Engine.
 *
 * Author:  Utkarsha Labs
 * Target:  x86-64 C/C++ Header
 * =============================================================================
 */

#ifndef UNET_C_API_H
#define UNET_C_API_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* System Initialization & Polling */
int unet_init(void);
void unet_poll(void);
void unet_shutdown(void);

/* POSIX BSD Socket API */
int unet_socket(int domain, int type, int protocol);
int unet_bind(int sockfd, const void *addr, uint32_t addrlen);
int unet_connect(int sockfd, const void *addr, uint32_t addrlen);
int unet_listen(int sockfd, int backlog);
int unet_accept(int sockfd, void *addr, uint32_t *addrlen);
ssize_t unet_send(int sockfd, const void *buf, size_t len, int flags);
ssize_t unet_recv(int sockfd, void *buf, size_t len, int flags);

/* Monolithic HTTP/1.1 Engine (RFC 9112 + RFC 10008 QUERY) */
int http1_parse_request(const char *buf, size_t len);
int http1_handle_query(const char *buf, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* UNET_C_API_H */
