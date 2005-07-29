/*
 *  libfb - FreeBASIC's runtime library
 *	Copyright (C) 2004-2005 Andre Victor T. Vicentini (av1ctor@yahoo.com.br)
 *
 *  This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Lesser General Public
 *  License as published by the Free Software Foundation; either
 *  version 2.1 of the License, or (at your option) any later version.
 *
 *  This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Lesser General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public
 *  License along with this library; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

/*
 * fb_dos.h -- common DOS definitions.
 *
 * chng: jul/2005 written [DrV]
 *
 */

#ifndef __FB_DOS_H__
#define __FB_DOS_H__

#define FB_DOS_USE_CONIO

#include <dpmi.h>
#include <dos.h>
#include <go32.h>
#include <pc.h>
#include <sys/farptr.h>

#ifdef FB_DOS_USE_CONIO
# include <conio.h>
#endif

typedef struct _FB_DOS_TXTMODE {
	int w;
	int h;
	unsigned long phys_addr;
} FB_DOS_TXTMODE;

extern FB_DOS_TXTMODE fb_dos_txtmode;

#endif
