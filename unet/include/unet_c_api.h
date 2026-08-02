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
int64_t unet_send(int sockfd, const void *buf, size_t len, int flags);
int64_t unet_recv(int sockfd, void *buf, size_t len, int flags);

/* Monolithic HTTP/1.1 Engine (RFC 9112 + RFC 10008 QUERY) */
int http1_parse_request(const char *buf, size_t len);
int http1_handle_query(const char *buf, size_t len);

/* Automotive Subsystem (DoIP & CAN-FD) */
int doip_process_packet(const uint8_t *buf, uint32_t len);
int can_eth_translate_frame(const void *canfd_frame, void *eth_buf);

/* Fintech Subsystem (ISO 8583, ISO 20022, SWIFT) */
int iso8583_parse_msg(const uint8_t *buf, uint32_t len);
int iso20022_parse_xml(const char *xml_buf, uint32_t len);
int swift_parse_fin(const char *fin_buf, uint32_t len);

/* Gaming Subsystem (RakNet & Esports Engine) */
int raknet_process_packet(const uint8_t *buf, uint32_t len);
int e2s_compress_delta_avx512(const void *curr_frame, const void *prev_frame, void *out_buf);

#ifdef __cplusplus
}
#endif

#endif /* UNET_C_API_H */
