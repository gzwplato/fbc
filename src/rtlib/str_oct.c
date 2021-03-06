/* oct$ routines */

#include "fb.h"

FBCALL FBSTRING *fb_OCT_b ( unsigned char num )
{
	return fb_OCTEx_l( num, 0 );
}

FBCALL FBSTRING *fb_OCT_s ( unsigned short num )
{
	return fb_OCTEx_l( num, 0 );
}

FBCALL FBSTRING *fb_OCT_i ( unsigned int num )
{
	return fb_OCTEx_l( num, 0 );
}

FBCALL FBSTRING *fb_OCTEx_b ( unsigned char num, int digits )
{
	return fb_OCTEx_l( num, digits );
}

FBCALL FBSTRING *fb_OCTEx_s ( unsigned short num, int digits )
{
	return fb_OCTEx_l( num, digits );
}

FBCALL FBSTRING *fb_OCTEx_i ( unsigned int num, int digits )
{
	return fb_OCTEx_l( num, digits );
}
