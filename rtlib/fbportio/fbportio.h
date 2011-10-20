#ifndef __FBPORTIO_H__
#define __FBPORTIO_H__

#define FBPORTIO_VERSION    256
#define FBPORTIO            32768
#define IOCTL_GRANT_IOPM    CTL_CODE(FBPORTIO, 2048, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_GET_VERSION   CTL_CODE(FBPORTIO, 2049, METHOD_BUFFERED, FILE_ANY_ACCESS)

#endif