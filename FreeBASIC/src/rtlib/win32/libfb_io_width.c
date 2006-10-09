/*
 *  libfb - FreeBASIC's runtime library
 *	Copyright (C) 2004-2006 Andre V. T. Vicentini (av1ctor@yahoo.com.br) and
 *  the FreeBASIC development team.
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
 *
 *  As a special exception, the copyright holders of this library give
 *  you permission to link this library with independent modules to
 *  produce an executable, regardless of the license terms of these
 *  independent modules, and to copy and distribute the resulting
 *  executable under terms of your choice, provided that you also meet,
 *  for each linked independent module, the terms and conditions of the
 *  license of that module. An independent module is a module which is
 *  not derived from or based on this library. If you modify this library,
 *  you may extend this exception to your version of the library, but
 *  you are not obligated to do so. If you do not wish to do so, delete
 *  this exception statement from your version.
 */

/*
 * io_width.c -- width (console, no gfx) for Windows
 *
 * credits: code based on PDCurses, Win32 port by Chris Szurgot (szurgot@itribe.net)
 *
 * chng: nov/2004 written [v1ctor]
 *
 */

#include "fb.h"

void fb_InitConsoleWindow( void );

/*:::::*/
int fb_ConsoleWidth( int cols, int rows )
{
   	COORD size, max;
    int cur, do_change = FALSE;
    int ncols, nrows;

    fb_InitConsoleWindow( );

    if( FB_CONSOLE_WINDOW_EMPTY() )
        return 0;

   	max = GetLargestConsoleWindowSize( __fb_out_handle );
    fb_hConsoleGetWindow( NULL, NULL, &ncols, &nrows );

    if( cols > 0 )
    {
        size.X = cols;
        do_change = TRUE;
    }
    else
    {
        size.X = (SHORT) ncols;
    }

    if( rows > 0 )
    {
        size.Y = rows;
        do_change = TRUE;
    }
    else
    {
        size.Y = (SHORT) nrows;
    }

    cur = size.X | (size.Y << 16);

    if( do_change ) {
        SMALL_RECT rect;
        rect.Left = rect.Top = 0;
        rect.Right = size.X - 1;
        if( rect.Right > max.X )
            rect.Right = max.X;

        rect.Bottom = rect.Top + size.Y - 1;
        if( rect.Bottom > max.Y )
            rect.Bottom = max.Y;

        /* Ensure that the window isn't larget than the destination screen
         * buffer size */
        if( rect.Bottom < (nrows-1) ) {
            SMALL_RECT rTmp;
            memcpy( &rTmp, &rect, sizeof(SMALL_RECT) );
            if( rTmp.Right >= ncols )
                rTmp.Right = ncols - 1;
            SetConsoleWindowInfo( __fb_out_handle, TRUE, &rTmp );
        } else if( rect.Right < (ncols-1) ) {
            SMALL_RECT rTmp;
            memcpy( &rTmp, &rect, sizeof(SMALL_RECT) );
            if( rTmp.Bottom >= nrows )
                rTmp.Bottom = nrows - 1;
            SetConsoleWindowInfo( __fb_out_handle, TRUE, &rTmp );
        }

        /* Now set the screen buffer size and ensure that the window is
         * large enough to show the whole buffer */
        SetConsoleScreenBufferSize( __fb_out_handle, size );
        SetConsoleWindowInfo( __fb_out_handle, TRUE, &rect );
#if 0
        /* Shouldn't be required any more ... */
        SetConsoleScreenBufferSize( __fb_out_handle, size );
        SetConsoleWindowInfo( __fb_out_handle, TRUE, &rect );
#endif
    }

    SetConsoleActiveScreenBuffer( __fb_out_handle );

    if( do_change ) {
        /* Re-enable updating */
        __fb_ConsoleSetByUser = FALSE;

        fb_hUpdateConsoleWindow( );

        __fb_ConsoleSetByUser = TRUE;
    }

	return cur;
}
