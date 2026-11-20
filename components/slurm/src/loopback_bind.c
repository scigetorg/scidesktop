/* Preloaded into slurmctld and slurmd by slurm-session: a socket they ask to
 * bind on every interface is bound to loopback instead.
 *
 * Slurm has no setting for the address its daemons listen on. Its only
 * alternative to every interface (CommunicationParameters=NoInAddrAny) is the
 * address the host name resolves to, which in a container is the address
 * other containers reach it at.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>

int bind(int fd, const struct sockaddr *address, socklen_t length)
{
    static int (*next)(int, const struct sockaddr *, socklen_t);
    struct sockaddr_in v4;
    struct sockaddr_in6 v6;

    if (!next)
        next = dlsym(RTLD_NEXT, "bind");
    if (address && address->sa_family == AF_INET && length >= sizeof(v4)) {
        memcpy(&v4, address, sizeof(v4));
        if (v4.sin_addr.s_addr == htonl(INADDR_ANY)) {
            v4.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
            return next(fd, (const struct sockaddr *)&v4, sizeof(v4));
        }
    } else if (address && address->sa_family == AF_INET6 && length >= sizeof(v6)) {
        memcpy(&v6, address, sizeof(v6));
        if (IN6_IS_ADDR_UNSPECIFIED(&v6.sin6_addr)) {
            v6.sin6_addr = in6addr_loopback;
            return next(fd, (const struct sockaddr *)&v6, sizeof(v6));
        }
    }
    return next(fd, address, length);
}
