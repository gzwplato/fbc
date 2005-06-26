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
 * array_tmpdesc.c -- temp descriptor core, for array fields passed by descriptor
 *
 * chng: jan/2005 written [v1ctor]
 *       feb/2005 modified to use the generic list routines [lillo]
 *
 */

#include <malloc.h>
#include <stdarg.h>
#include <stddef.h>
#include "fb.h"


/**********
 * temp array descriptors
 **********/

static FB_LIST tmpdsList = { 0 };

static FB_ARRAY_TMPDESC fb_tmpdsTB[FB_ARRAY_TMPDESCRIPTORS];

/*:::::*/
FBARRAY *fb_hArrayAllocTmpDesc( void )
{
	FB_ARRAY_TMPDESC *dsc;

	if( (tmpdsList.fhead == NULL) && (tmpdsList.head == NULL) )
		fb_hListInit( &tmpdsList, (void *)fb_tmpdsTB, sizeof(FB_ARRAY_TMPDESC), FB_ARRAY_TMPDESCRIPTORS );

	dsc = (FB_ARRAY_TMPDESC *)fb_hListAllocElem( &tmpdsList );
	if( dsc == NULL )
		return NULL;

	return (FBARRAY *)&dsc->array;
}

/*:::::*/
void fb_hArrayFreeTmpDesc( FBARRAY *src )
{
	FB_ARRAY_TMPDESC *dsc;

	dsc = (FB_ARRAY_TMPDESC *)((char *)src - offsetof(FB_ARRAY_TMPDESC, array));

	fb_hListFreeElem( &tmpdsList, (FB_LISTELEM *)dsc );
}

/*:::::*/
FBARRAY *fb_ArrayAllocTempDesc( FBARRAY **pdesc, void *arraydata, int element_len, int dimensions, ... )
{
    va_list 	ap;
    int			i;
    int			elements, diff;
    FBARRAY		*array;
    FBARRAYDIM	*p;
    int			lbTB[FB_MAXDIMENSIONS];
    int			ubTB[FB_MAXDIMENSIONS];

	FB_LOCK();
	
    array = fb_hArrayAllocTmpDesc( );

    if( array != NULL )
    {
    	if( dimensions == 0) {

    		/* special case for GET temp arrays */
    		array->size = 0;
    		*pdesc = array;
			
			FB_UNLOCK();
			
       		return array;
    	}
    	
    	va_start( ap, dimensions );

    	p = &array->dimTB[0];

    	for( i = 0; i < dimensions; i++ )
    	{
    		lbTB[i] = va_arg( ap, int );
    		ubTB[i] = va_arg( ap, int );

    		p->elements = (ubTB[i] - lbTB[i]) + 1;
    		p->lbound 	= lbTB[i];
    		++p;
    	}

    	va_end( ap );

    	elements = fb_hArrayCalcElements( dimensions, &lbTB[0], &ubTB[0] );
    	diff 	 = fb_hArrayCalcDiff( dimensions, &lbTB[0], &ubTB[0] ) * element_len;

    	array->element_len = element_len;
    	array->dimensions  = dimensions;

    	array->ptr 	= arraydata;
    	array->data = ((unsigned char *) array->ptr) + diff;
    	array->size	= elements * element_len;
    	
    }
    
    FB_UNLOCK();

    *pdesc = array;

    return array;
}

/*:::::*/
FBCALL void fb_ArrayFreeTempDesc( FBARRAY *pdesc )
{

	FB_LOCK();

	fb_hArrayFreeTmpDesc( pdesc );

	FB_UNLOCK();

}








