/*
  menu_test.c - the OSD menu on the host (make menu-test).

  menu.c is compiled with -DSDL, which is its host switch: no FreeRTOS,
  menu_init() takes a u8g2 to draw into.  Everything else it calls is
  stubbed here - the card has three files a slot, the core takes the
  values into a log - and the menu is driven through menu_do() with the
  events usb_host.c would send.  Each screen worth looking at is dumped
  as a 128x64 text bitmap under the directory given as the first
  argument (tools/osd_png.py makes PNGs of them), and the things that
  can be asserted are: which form is open and which entry is highlighted
  after a key, what the core was sent, what the main form offers, and
  that the text page scrolls and returns.

  The walk: the main form, Hardware, every value stepped with the cursor
  keys (and Space) both ways and back, ESC (the OSD closes and reopens on
  the same form), the title back to the main form, About opened,
  scrolled and closed, Reset, Save settings.
*/
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "u8g2.h"
#include "ff.h"
#include "diskio.h"
#include "sysctrl.h"
#include "sdc.h"
#include "menu.h"

unsigned char core_id = CORE_ID_PK8000;

//------------------------------------------------------------------------
// stubs
//------------------------------------------------------------------------
void vTaskDelay(int ms) { (void)ms; }
void sdc_lock(void) {}
void sdc_unlock(void) {}
int  sdc_is_ready(void) { return 1; }

// the OSD's visibility, as osd_enable() would set it
static int osd_visible;
void osd_enable(osd_t *osd, char en) { (void)osd; osd_visible = en; }

// FatFs never gets a volume here: f_open fails and the menu takes its
// defaults, which is the path a card without an .ini takes
DSTATUS disk_initialize(BYTE p) { (void)p; return STA_NOINIT; }
DSTATUS disk_status(BYTE p) { (void)p; return STA_NOINIT; }
DRESULT disk_read(BYTE p, BYTE *b, LBA_t s, UINT c) { (void)p; (void)b; (void)s; (void)c; return RES_NOTRDY; }
DRESULT disk_write(BYTE p, const BYTE *b, LBA_t s, UINT c) { (void)p; (void)b; (void)s; (void)c; return RES_NOTRDY; }
DRESULT disk_ioctl(BYTE p, BYTE c, void *b) { (void)p; (void)c; (void)b; return RES_NOTRDY; }

// what the core was told: a log of (id, value)
static char set_log[256][2];
static int  set_n;
void sys_set_val(spi_t *spi, char id, uint8_t v) {
  (void)spi;
  if(set_n < 256) { set_log[set_n][0] = id; set_log[set_n][1] = v; }
  set_n++;
}
static int set_last(char id) {
  for(int i=set_n-1;i>=0;i--) if(set_log[i][0] == id) return set_log[i][1];
  return -1;
}
static int set_count(char id) {
  int n = 0;
  for(int i=0;i<set_n;i++) if(set_log[i][0] == id) n++;
  return n;
}

// the card: one directory a slot, three files each
static char *cwd[MAX_DRIVES];
static char *image_name[MAX_DRIVES];
char *sdc_get_image_name(int drive) { return image_name[drive]; }
char *sdc_get_cwd(int drive) { if(!cwd[drive]) cwd[drive] = strdup(CARD_MOUNTPOINT); return cwd[drive]; }
void sdc_set_default(int drive, const char *name) { (void)drive; (void)name; }
int sdc_image_open(int drive, char *name) {
  if(image_name[drive]) free(image_name[drive]);
  image_name[drive] = name ? strdup(name) : NULL;
  return 0;
}
sdc_dir_t *sdc_readdir(int drive, char *name, const char *exts) {
  static sdc_dir_entry_t files[4];
  static sdc_dir_t dir = { 4, files };
  static char n0[] = "/No Disk", n1[64], n2[64], n3[64];
  (void)drive; (void)name;
  char ext[8] = "dsk";
  sscanf(exts, "%7[a-z]", ext);
  files[0].name = n0; files[0].is_dir = 1;
  snprintf(n1, sizeof(n1), "GAME.%s", ext); files[1].name = n1; files[1].is_dir = 0;
  snprintf(n2, sizeof(n2), "SYSTEM.%s", ext); files[2].name = n2; files[2].is_dir = 0;
  snprintf(n3, sizeof(n3), "A rather long file name that has to scroll.%s", ext); files[3].name = n3; files[3].is_dir = 0;
  return &dir;
}

//------------------------------------------------------------------------
// the screen
//------------------------------------------------------------------------
static u8g2_t u8g2;
static const char *outdir = ".";
static int shots;

static void shot(const char *name) {
  char path[256];
  snprintf(path, sizeof(path), "%s/%02d-%s.txt", outdir, ++shots, name);
  FILE *f = fopen(path, "w");
  if(!f) { perror(path); exit(1); }
  for(int y=0;y<64;y++) {
    for(int x=0;x<128;x++) fputc(u8x8_GetBitmapPixel(u8g2_GetU8x8(&u8g2), x, y) ? '#' : '.', f);
    fputc('\n', f);
  }
  fclose(f);
}

static int errors;
#define CHECK(cond, ...) do { if(!(cond)) { errors++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while(0)

// the value the highlighted 'L' entry shows, to check it against the core
static int stepped(menu_t *menu, char id, int step, int expect) {
  menu_do(menu, step > 0 ? MENU_EVENT_RIGHT : MENU_EVENT_LEFT);
  return set_last(id) == expect;
}

int main(int argc, char **argv) {
  if(argc > 1) outdir = argv[1];

  u8g2_SetupBitmap(&u8g2, &u8g2_cb_r0, 128, 64);
  u8x8_InitDisplay(u8g2_GetU8x8(&u8g2));

  menu_t *menu = menu_init(&u8g2);
  menu_do(menu, MENU_EVENT_SHOW);
  shot("main");

  //---- the main form: Reset, Hardware, About, Save settings
  CHECK(menu->form == 0 && menu->entry == 1, "start: form %d entry %d", menu->form, menu->entry);
  CHECK(strstr(menu->forms[0], "PK8000 Nano,;") == menu->forms[0], "main form title: %s", menu->forms[0]);
  CHECK(strstr(menu->forms[0], "B,Reset,R;") && strstr(menu->forms[0], "S,Hardware,1;") &&
        strstr(menu->forms[0], "T,About,;") && strstr(menu->forms[0], "B,Save settings,S;"),
        "main form entries: %s", menu->forms[0]);
  CHECK(menu->entries == 5, "main form has %d entries, expected 5", menu->entries);
  CHECK(strstr(menu->forms[0], "F,") == NULL, "main form has a file selector");

  //---- the defaults went to the core, every letter once, then the reset
  const char *letters = "Abwj";
  for(const char *l = letters; *l; l++)
    CHECK(set_count(*l) == 1, "letter %c sent %d times at start", *l, set_count(*l));
  CHECK(set_last('A') == 1 && set_last('b') == 1 && set_last('w') == 1 && set_last('j') == 0, "defaults wrong");
  CHECK(set_count('R') == 2 && set_last('R') == 0, "start reset: R sent %d times, last %d", set_count('R'), set_last('R'));
  for(const char *l = "VPZeutMSHICY123cfpqrsKJDymdhn"; *l; l++)
    CHECK(set_last(*l) == -1, "the foreign letter %c is sent", *l);

  //---- left/right on a button or submenu entry do nothing
  int n = set_n;
  menu_do(menu, MENU_EVENT_LEFT); menu_do(menu, MENU_EVENT_RIGHT);
  CHECK(set_n == n && menu->form == 0 && menu->entry == 1, "left/right on Reset did something");

  //---- Hardware
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 2, "after a down entry %d, expected 2 (Hardware)", menu->entry);
  menu_do(menu, MENU_EVENT_LEFT); menu_do(menu, MENU_EVENT_RIGHT);
  CHECK(set_n == n && menu->form == 0 && menu->entry == 2, "left/right on Hardware did something");
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 1 && menu->entry == 1, "Hardware: form %d entry %d", menu->form, menu->entry);
  CHECK(menu->entries == 5, "Hardware has %d entries, expected 5", menu->entries);
  shot("hardware");

  //---- Volume: right, left, both wrap, Space steps on
  n = set_n;
  CHECK(stepped(menu, 'A', +1, 2) && set_n == n+1, "right on Volume: A=%d", set_last('A'));
  CHECK(stepped(menu, 'A', -1, 1), "left on Volume: A=%d", set_last('A'));
  CHECK(stepped(menu, 'A', -1, 0), "left to Mute: A=%d", set_last('A'));
  CHECK(stepped(menu, 'A', -1, 3), "left wraps to 100%%: A=%d", set_last('A'));
  CHECK(stepped(menu, 'A', +1, 0), "right wraps to Mute: A=%d", set_last('A'));
  CHECK(stepped(menu, 'A', +1, 1), "right to 33%%: A=%d", set_last('A'));
  menu_do(menu, MENU_EVENT_SELECT);  // space steps on: 66%
  CHECK(set_last('A') == 2, "space on Volume: A=%d", set_last('A'));
  shot("hardware-volume-66");
  CHECK(stepped(menu, 'A', -1, 1), "back to 33%%: A=%d", set_last('A'));

  //---- Beeper
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 2, "Beeper entry %d", menu->entry);
  CHECK(stepped(menu, 'b', +1, 0), "right on Beeper: b=%d", set_last('b'));
  shot("hardware-beeper-mute");
  CHECK(stepped(menu, 'b', +1, 1), "right wraps Beeper on: b=%d", set_last('b'));
  CHECK(stepped(menu, 'b', -1, 0), "left on Beeper: b=%d", set_last('b'));
  CHECK(stepped(menu, 'b', -1, 1), "left wraps Beeper on: b=%d", set_last('b'));

  //---- CPU waits
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 3, "CPU waits entry %d", menu->entry);
  CHECK(stepped(menu, 'w', +1, 0), "right on CPU waits: w=%d", set_last('w'));
  CHECK(stepped(menu, 'w', +1, 1), "right wraps CPU waits on: w=%d", set_last('w'));
  CHECK(stepped(menu, 'w', -1, 0), "left on CPU waits: w=%d", set_last('w'));
  shot("hardware-waits-off");
  CHECK(stepped(menu, 'w', -1, 1), "left wraps CPU waits on: w=%d", set_last('w'));

  //---- Joysticks
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 4, "Joysticks entry %d", menu->entry);
  CHECK(stepped(menu, 'j', +1, 1), "right on Joysticks: j=%d", set_last('j'));
  shot("hardware-joy-swapped");
  CHECK(stepped(menu, 'j', +1, 0), "right wraps Joysticks: j=%d", set_last('j'));
  CHECK(stepped(menu, 'j', -1, 1), "left on Joysticks: j=%d", set_last('j'));
  CHECK(stepped(menu, 'j', -1, 0), "left wraps Joysticks: j=%d", set_last('j'));
  CHECK(set_count('A') == 9 && set_count('b') == 5 && set_count('w') == 5 && set_count('j') == 5,
        "sends: A %d b %d w %d j %d", set_count('A'), set_count('b'), set_count('w'), set_count('j'));

  //---- paging and wrapping in Hardware
  menu_do(menu, MENU_EVENT_PGUP);
  CHECK(menu->entry == 1, "PGUP in Hardware: entry %d", menu->entry);
  menu_do(menu, MENU_EVENT_PGDOWN);
  CHECK(menu->entry == 4, "PGDOWN in Hardware: entry %d", menu->entry);
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 0, "DOWN past Joysticks: entry %d, expected the title", menu->entry);
  menu_do(menu, MENU_EVENT_UP);
  CHECK(menu->entry == 4, "UP from the title: entry %d, expected 4", menu->entry);

  //---- ESC closes the OSD; F12 opens it again on the same form
  menu_do(menu, MENU_EVENT_HIDE);
  CHECK(!osd_visible, "ESC left the OSD visible");
  menu_do(menu, MENU_EVENT_SHOW);
  CHECK(osd_visible && menu->form == 1 && menu->entry == 4, "after ESC and F12: form %d entry %d", menu->form, menu->entry);

  //---- the title returns to the entry that opened the form
  menu_do(menu, MENU_EVENT_DOWN);    // wraps to the title
  CHECK(menu->entry == 0, "Hardware title: entry %d", menu->entry);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 0 && menu->entry == 2, "back from Hardware: form %d entry %d, expected 0/2", menu->form, menu->entry);
  shot("main-back");

  //---- About: a text page that scrolls and returns
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 3, "About entry %d", menu->entry);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == MENU_FORM_TEXT && menu->offset == 0, "About: form %d offset %d", menu->form, menu->offset);
  shot("about-0");
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->offset == 1, "About scrolled to %d", menu->offset);
  menu_do(menu, MENU_EVENT_PGDOWN);
  CHECK(menu->offset == 5, "About paged to %d, expected 5", menu->offset);
  shot("about-5");
  for(int i=0;i<60;i++) menu_do(menu, MENU_EVENT_DOWN);
  int last = menu->offset;
  CHECK(last > 5 && last < 44, "About scrolled to the end at %d", last);
  shot("about-end");
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->offset == last, "About scrolls past its end");
  menu_do(menu, MENU_EVENT_UP);
  CHECK(menu->offset == last-1, "About does not scroll back");
  menu_do(menu, MENU_EVENT_PGUP); menu_do(menu, MENU_EVENT_PGUP); menu_do(menu, MENU_EVENT_PGUP); menu_do(menu, MENU_EVENT_PGUP);
  CHECK(menu->offset == 0, "About does not page back to the top (%d)", menu->offset);
  n = set_n;
  menu_do(menu, MENU_EVENT_LEFT); menu_do(menu, MENU_EVENT_RIGHT);
  CHECK(set_n == n && menu->form == MENU_FORM_TEXT, "left/right on About did something");
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 0 && menu->entry == 3, "back from About: form %d entry %d", menu->form, menu->entry);

  //---- Reset: the core is pulsed and the OSD closes
  menu_do(menu, MENU_EVENT_UP); menu_do(menu, MENU_EVENT_UP);   // Reset
  CHECK(menu->entry == 1, "Reset entry %d", menu->entry);
  n = set_count('R');
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(set_count('R') == n+2 && set_last('R') == 0 && set_log[set_n-2][0] == 'R' && set_log[set_n-2][1] == 1,
        "Reset: R sent %d more times, last %d", set_count('R') - n, set_last('R'));
  CHECK(!osd_visible, "Reset left the OSD visible");
  CHECK(menu->form == 0 && menu->entry == 1, "after Reset: form %d entry %d", menu->form, menu->entry);
  menu_do(menu, MENU_EVENT_SHOW);

  //---- Save settings is a button on the main form: it writes the card (fails here, no card)
  menu_do(menu, MENU_EVENT_PGDOWN);
  CHECK(menu->entry == 4, "Save settings entry %d", menu->entry);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 0 && menu->entry == 4, "Save settings left the main form");
  shot("main-end");
  menu_do(menu, MENU_EVENT_HIDE);

  printf("menu-test: %d screens in %s, %d error(s)\n", shots, outdir, errors);
  return errors ? 1 : 0;
}
