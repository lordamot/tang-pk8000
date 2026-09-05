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
  after a key, what the core was sent, which slot and extensions a file
  selector asks the card for, what image it opens, what the main form
  offers, and that the text page scrolls and returns.

  The walk: the main form, its four file selectors (each entered, closed
  with ESC and reopened, left by the title; the tape one also loads and
  ejects an image), Run .bas (a file chosen goes to bas_run, not to a
  slot, and closes the OSD), Reset, Hardware: every value stepped with the cursor
  keys (and Space) both ways and back, the ROM disk selector, the Rewind
  button, the scrolling of the long form, paging, ESC (the OSD closes and
  reopens on the same form), the title back to the main form, About
  opened, scrolled and closed, Save settings.
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
#include "bas.h"
#include "menu.h"

unsigned char core_id = CORE_ID_PK8000;

//------------------------------------------------------------------------
// stubs
//------------------------------------------------------------------------
void vTaskDelay(int ms) { (void)ms; }
static char bas_path[256];                   // the last bas_run()
static int  bas_n;
int  bas_run(spi_t *spi, const char *path) { (void)spi; snprintf(bas_path, sizeof(bas_path), "%s", path); bas_n++; return 0; }
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
void sys_get_debug(spi_t *spi, unsigned char *buf, int len) { (void)spi; memset(buf, 0, len); }
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
static int  open_drive = -1, open_n;          // the last sdc_image_open()
static int  readdir_drive = -1;               // the last sdc_readdir()
static const char *readdir_exts;
char *sdc_get_image_name(int drive) { return image_name[drive]; }
char *sdc_get_cwd(int drive) { if(!cwd[drive]) cwd[drive] = strdup(CARD_MOUNTPOINT); return cwd[drive]; }
void sdc_set_default(int drive, const char *name) { (void)drive; (void)name; }
int sdc_image_open(int drive, char *name) {
  assert(drive >= 0 && drive < MAX_DRIVES);
  if(image_name[drive]) free(image_name[drive]);
  image_name[drive] = name ? strdup(name) : NULL;
  open_drive = drive; open_n++;
  return 0;
}
sdc_dir_t *sdc_readdir(int drive, char *name, const char *exts) {
  static sdc_dir_entry_t files[4];
  static sdc_dir_t dir = { 4, files };
  static char n0[] = "/No Disk", n1[64], n2[64], n3[64];
  assert(drive >= 0 && drive < MAX_DRIVES);
  (void)name;
  readdir_drive = drive; readdir_exts = exts;
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

// the extension list a selector asked for: ';' terminated in the form
static int exts_are(const char *want) {
  return readdir_exts && strncmp(readdir_exts, want, strlen(want)) == 0 && readdir_exts[strlen(want)] == ';';
}

// the highlighted entry is the title or one of the four rows on screen
#define CHECK_VISIBLE(menu) CHECK((menu)->entry - (menu)->offset >= ((menu)->entry ? 1 : 0) && (menu)->entry - (menu)->offset <= 4 && \
                                  (menu)->offset >= 0 && (menu)->offset <= (menu)->entries - 5, \
                                  "entry %d off screen: offset %d of %d", (menu)->entry, (menu)->offset, (menu)->entries)

// a file selector on the current entry of a form: opened, closed with
// ESC and reopened, left by its title back to the entry it came from
static void selector(menu_t *menu, const char *what, int form, int entry, int drive, const char *exts) {
  int n = set_n;
  menu_do(menu, MENU_EVENT_LEFT); menu_do(menu, MENU_EVENT_RIGHT);
  CHECK(set_n == n && menu->form == form && menu->entry == entry, "%s: left/right on the selector entry did something", what);
  readdir_drive = -1; readdir_exts = NULL;
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == MENU_FORM_FSEL, "%s: selector not open, form %d", what, menu->form);
  CHECK(menu->entries == 5, "%s: selector shows %d entries, expected 5 (No Disk + 3 files)", what, menu->entries);
  CHECK(readdir_drive == drive, "%s: selector read slot %d, expected %d", what, readdir_drive, drive);
  CHECK(exts_are(exts), "%s: selector asked for '%.12s', expected '%s'", what, readdir_exts ? readdir_exts : "(null)", exts);
  menu_do(menu, MENU_EVENT_HIDE);
  CHECK(!osd_visible && menu->form == MENU_FORM_FSEL, "%s: ESC on the selector", what);
  menu_do(menu, MENU_EVENT_SHOW);
  CHECK(osd_visible && menu->form == MENU_FORM_FSEL, "%s: the selector did not come back", what);
  while(menu->entry) menu_do(menu, MENU_EVENT_UP);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == form && menu->entry == entry, "%s: back from the selector: form %d entry %d, expected %d/%d",
        what, menu->form, menu->entry, form, entry);
}

// the selector on the current entry loads its second file into `drive`,
// then ejects it through "No Disk"
static void load_and_eject(menu_t *menu, const char *what, int form, int entry, int drive, const char *file) {
  int n = open_n;
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == MENU_FORM_FSEL && menu->entry == 1, "%s: selector opens on entry %d", what, menu->entry);
  menu_do(menu, MENU_EVENT_DOWN);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(open_n == n+1 && open_drive == drive, "%s: image opened %d times, on slot %d", what, open_n - n, open_drive);
  CHECK(image_name[drive] && strcmp(image_name[drive], file) == 0, "%s: slot %d holds '%s', expected '%s'",
        what, drive, image_name[drive] ? image_name[drive] : "(null)", file);
  CHECK(menu->form == form && menu->entry == entry, "%s: after loading: form %d entry %d", what, menu->form, menu->entry);
  menu_do(menu, MENU_EVENT_SELECT);       // reopened, it highlights the loaded file
  CHECK(menu->form == MENU_FORM_FSEL && menu->entry == 2, "%s: selector reopens on entry %d, expected the file", what, menu->entry);
  menu_do(menu, MENU_EVENT_UP);           // No Disk
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(open_n == n+2 && open_drive == drive && !image_name[drive], "%s: No Disk did not eject slot %d", what, drive);
  CHECK(menu->form == form && menu->entry == entry, "%s: after ejecting: form %d entry %d", what, menu->form, menu->entry);
}

// an On/Off 'L' entry with default `def`: right, right wraps, left, left wraps
static void toggle(menu_t *menu, const char *what, char id, int def) {
  int n = set_n;
  CHECK(stepped(menu, id, +1, !def), "right on %s: %c=%d", what, id, set_last(id));
  CHECK(stepped(menu, id, +1,  def), "right wraps %s: %c=%d", what, id, set_last(id));
  CHECK(stepped(menu, id, -1, !def), "left on %s: %c=%d", what, id, set_last(id));
  CHECK(stepped(menu, id, -1,  def), "left wraps %s: %c=%d", what, id, set_last(id));
  CHECK(set_n == n+4, "%s: %d sends for four steps", what, set_n - n);
}

int main(int argc, char **argv) {
  if(argc > 1) outdir = argv[1];

  u8g2_SetupBitmap(&u8g2, &u8g2_cb_r0, 128, 64);
  u8x8_InitDisplay(u8g2_GetU8x8(&u8g2));

  menu_t *menu = menu_init(&u8g2);
  menu_do(menu, MENU_EVENT_SHOW);
  shot("main");

  //---- the main form: four image slots, Run .bas, Reset, Hardware, About, Debug, Save settings
  CHECK(menu->form == 0 && menu->entry == 1, "start: form %d entry %d", menu->form, menu->entry);
  CHECK(strstr(menu->forms[0], "PK8000 Nano,;") == menu->forms[0], "main form title: %s", menu->forms[0]);
  CHECK(strstr(menu->forms[0], "F,Tape:,0|cas;") && strstr(menu->forms[0], "F,Floppy A:,1|fdd;") &&
        strstr(menu->forms[0], "F,Floppy B:,2|fdd;") && strstr(menu->forms[0], "F,Hard disk:,3|img+hdd;") &&
        strstr(menu->forms[0], "F,Run .bas:,5|bas;") &&
        strstr(menu->forms[0], "B,Reset,R;") && strstr(menu->forms[0], "S,Hardware,1;") &&
        strstr(menu->forms[0], "T,About,;") && strstr(menu->forms[0], "T,Debug,;") &&
        strstr(menu->forms[0], "B,Save settings,S;"),
        "main form entries: %s", menu->forms[0]);
  CHECK(menu->entries == 11, "main form has %d entries, expected 11", menu->entries);
  CHECK(strstr(menu->forms[1], "Hardware,0|7;") == menu->forms[1], "Hardware title: %s", menu->forms[1]);
  CHECK(strstr(menu->forms[1], "L,Floppy:,Off|On,f;") && strstr(menu->forms[1], "L,IDE:,Off|On,i;") &&
        strstr(menu->forms[1], "L,ROM disk:,Off|On,r;") && strstr(menu->forms[1], "F,ROM file:,4|bin+rom;") &&
        strstr(menu->forms[1], "B,Rewind tape,e;"),
        "Hardware entries: %s", menu->forms[1]);

  //---- the defaults went to the core, every letter once and in order, then the reset
  {
    static const char init_log[][2] = {
      {'A',1}, {'b',1}, {'w',1}, {'j',0}, {'f',0}, {'i',0}, {'r',0}, {'T',1}, {'y',1}, {'p',0}, {'q',0}, {'K',0}, {'R',3}, {'R',0} };
    int init_n = sizeof(init_log)/sizeof(init_log[0]);
    CHECK(set_n == init_n, "%d values sent at start, expected %d", set_n, init_n);
    for(int i=0;i<init_n && i<set_n;i++)
      CHECK(set_log[i][0] == init_log[i][0] && set_log[i][1] == init_log[i][1],
            "start send %d is %c=%d, expected %c=%d", i, set_log[i][0], set_log[i][1], init_log[i][0], init_log[i][1]);
  }
  for(const char *l = "AbwjfirTypqK"; *l; l++)
    CHECK(set_count(*l) == 1, "letter %c sent %d times at start", *l, set_count(*l));
  CHECK(set_count('R') == 2 && set_last('R') == 0, "start reset: R sent %d times, last %d", set_count('R'), set_last('R'));
  for(const char *l = "VPZeutMSHICY123csJDmdhnBEGNOQUWXZ#<>"; *l; l++)
    CHECK(set_last(*l) == -1, "the foreign letter %c is sent", *l);
  CHECK(open_n == 0, "an image was opened at start with no settings");

  //---- the four file selectors of the main form
  selector(menu, "Tape", 0, 1, 0, "cas");
  shot("main-tape");
  menu_do(menu, MENU_EVENT_SELECT);
  shot("tape-selector");
  while(menu->entry) menu_do(menu, MENU_EVENT_UP);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 0 && menu->entry == 1, "back from the tape selector: form %d entry %d", menu->form, menu->entry);
  load_and_eject(menu, "Tape", 0, 1, 0, "GAME.cas");

  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 2, "Floppy A entry %d", menu->entry);
  selector(menu, "Floppy A", 0, 2, 1, "fdd");
  load_and_eject(menu, "Floppy A", 0, 2, 1, "GAME.fdd");
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 3, "Floppy B entry %d", menu->entry);
  selector(menu, "Floppy B", 0, 3, 2, "fdd");
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 4, "Hard disk entry %d", menu->entry);
  selector(menu, "Hard disk", 0, 4, 3, "img+hdd");
  load_and_eject(menu, "Hard disk", 0, 4, 3, "GAME.img");
  CHECK_VISIBLE(menu);

  //---- Run .bas: a selector on drive 5; a file chosen is run, not mounted
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 5, "Run .bas entry %d", menu->entry);
  selector(menu, "Run .bas", 0, 5, BAS_DRIVE, "bas");
  int n = open_n; bas_n = 0;
  menu_do(menu, MENU_EVENT_SELECT);
  menu_do(menu, MENU_EVENT_DOWN);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(bas_n == 1 && strstr(bas_path, "/GAME.bas"), "Run .bas: bas_run called %d times with '%s'", bas_n, bas_path);
  CHECK(open_n == n, "Run .bas mounted an image");
  CHECK(!osd_visible, "Run .bas left the OSD visible");
  CHECK(menu->form == 0 && menu->entry == 5, "after Run .bas: form %d entry %d", menu->form, menu->entry);
  menu_do(menu, MENU_EVENT_SHOW);
  shot("main-runbas");

  //---- Reset: the core is pulsed and the OSD closes
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 6, "Reset entry %d", menu->entry);
  CHECK_VISIBLE(menu);
  shot("main-reset");
  n = set_n;
  menu_do(menu, MENU_EVENT_LEFT); menu_do(menu, MENU_EVENT_RIGHT);
  CHECK(set_n == n && menu->form == 0 && menu->entry == 6, "left/right on Reset did something");
  n = set_count('R');
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(set_count('R') == n+2 && set_last('R') == 0 && set_log[set_n-2][0] == 'R' && set_log[set_n-2][1] == 1,
        "Reset: R sent %d more times, last %d", set_count('R') - n, set_last('R'));
  CHECK(!osd_visible, "Reset left the OSD visible");
  CHECK(menu->form == 0 && menu->entry == 6, "after Reset: form %d entry %d", menu->form, menu->entry);
  menu_do(menu, MENU_EVENT_SHOW);

  //---- Hardware
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 7, "after a down entry %d, expected 7 (Hardware)", menu->entry);
  CHECK_VISIBLE(menu);
  n = set_n;
  menu_do(menu, MENU_EVENT_LEFT); menu_do(menu, MENU_EVENT_RIGHT);
  CHECK(set_n == n && menu->form == 0 && menu->entry == 7, "left/right on Hardware did something");
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 1 && menu->entry == 1 && menu->offset == 0, "Hardware: form %d entry %d offset %d", menu->form, menu->entry, menu->offset);
  CHECK(menu->entries == 15, "Hardware has %d entries, expected 15", menu->entries);
  shot("hardware");

  //---- the three expansion switches: Off|On each, independent of each other
  n = set_n;
  toggle(menu, "Floppy", 'f', 0);
  CHECK(stepped(menu, 'f', +1, 1), "Floppy on: f=%d", set_last('f'));
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 2, "IDE entry %d", menu->entry);
  toggle(menu, "IDE", 'i', 0);
  CHECK(stepped(menu, 'i', +1, 1), "IDE on: i=%d", set_last('i'));
  CHECK(set_last('f') == 1, "turning the IDE on changed the floppy (f=%d)", set_last('f'));
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 3, "ROM disk entry %d", menu->entry);
  toggle(menu, "ROM disk", 'r', 0);
  shot("hardware-expansion-two-on");
  CHECK(set_n == n+14, "expansion switches: %d sends for fourteen steps", set_n - n);
  menu_do(menu, MENU_EVENT_UP); menu_do(menu, MENU_EVENT_UP);
  CHECK(stepped(menu, 'f', -1, 0), "Floppy off: f=%d", set_last('f'));
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(stepped(menu, 'i', -1, 0), "IDE off: i=%d", set_last('i'));
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 3, "back on ROM disk: entry %d", menu->entry);

  //---- ROM file: the fifth slot, from the Hardware form
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 4, "ROM file entry %d", menu->entry);
  selector(menu, "ROM file", 1, 4, 4, "bin+rom");
  load_and_eject(menu, "ROM file", 1, 4, 4, "GAME.bin");
  CHECK(menu->entries == 15 && menu->entry == 4, "back in Hardware: %d entries entry %d", menu->entries, menu->entry);
  CHECK_VISIBLE(menu);

  //---- Tape: Play by default
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 5, "Tape entry %d", menu->entry);
  toggle(menu, "Tape", 'T', 1);
  CHECK(stepped(menu, 'T', +1, 0), "Tape to Stop: T=%d", set_last('T'));
  shot("hardware-tape-stop");
  CHECK(stepped(menu, 'T', +1, 1), "Tape to Play: T=%d", set_last('T'));

  //---- Rewind tape: a button that pulses 'e' and keeps the OSD open
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 6, "Rewind entry %d", menu->entry);
  CHECK_VISIBLE(menu);
  n = set_n;
  menu_do(menu, MENU_EVENT_LEFT); menu_do(menu, MENU_EVENT_RIGHT);
  CHECK(set_n == n && menu->form == 1 && menu->entry == 6, "left/right on Rewind did something");
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(set_n == n+2 && set_log[n][0] == 'e' && set_log[n][1] == 1 && set_log[n+1][0] == 'e' && set_log[n+1][1] == 0,
        "Rewind: %d sends, expected e=1 then e=0", set_n - n);
  CHECK(osd_visible, "Rewind closed the OSD");
  CHECK(menu->form == 1 && menu->entry == 6, "after Rewind: form %d entry %d", menu->form, menu->entry);
  CHECK(set_count('R') == 4, "Rewind reset the core (R sent %d times)", set_count('R'));
  shot("hardware-rewind");

  //---- AY card
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 7, "AY card entry %d", menu->entry);
  CHECK_VISIBLE(menu);
  toggle(menu, "AY card", 'y', 1);

  //---- Volume: right, left, both wrap, Space steps on
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 8, "Volume entry %d", menu->entry);
  CHECK_VISIBLE(menu);
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
  CHECK(set_n == n+8, "Volume: %d sends for eight steps", set_n - n);

  //---- Beeper
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 9, "Beeper entry %d", menu->entry);
  CHECK_VISIBLE(menu);
  toggle(menu, "Beeper", 'b', 1);

  //---- CPU waits
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 10, "CPU waits entry %d", menu->entry);
  CHECK_VISIBLE(menu);
  toggle(menu, "CPU waits", 'w', 1);
  CHECK(stepped(menu, 'w', -1, 0), "CPU waits off: w=%d", set_last('w'));
  shot("hardware-waits-off");
  CHECK(stepped(menu, 'w', -1, 1), "CPU waits on: w=%d", set_last('w'));

  //---- Joysticks
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 11, "Joysticks entry %d", menu->entry);
  CHECK_VISIBLE(menu);
  toggle(menu, "Joysticks", 'j', 0);

  //---- the three write protections
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 12, "Floppy A prot. entry %d", menu->entry);
  CHECK_VISIBLE(menu);
  toggle(menu, "Floppy A prot.", 'p', 0);
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 13, "Floppy B prot. entry %d", menu->entry);
  CHECK_VISIBLE(menu);
  toggle(menu, "Floppy B prot.", 'q', 0);
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 14, "HDD prot. entry %d", menu->entry);
  CHECK_VISIBLE(menu);
  CHECK(menu->offset == 10, "at the end of Hardware the offset is %d, expected 10", menu->offset);
  toggle(menu, "HDD prot.", 'K', 0);
  CHECK(stepped(menu, 'K', +1, 1), "HDD prot. on: K=%d", set_last('K'));
  shot("hardware-end-hddprot");
  CHECK(stepped(menu, 'K', -1, 0), "HDD prot. off: K=%d", set_last('K'));

  // every list letter: its default at start, then the steps above
  CHECK(set_count('f') == 7 && set_count('i') == 7 && set_count('r') == 5 && set_count('T') == 7 && set_count('y') == 5 && set_count('A') == 9 &&
        set_count('b') == 5 && set_count('w') == 7 && set_count('j') == 5 &&
        set_count('p') == 5 && set_count('q') == 5 && set_count('K') == 7 && set_count('e') == 2,
        "sends: f %d i %d r %d T %d y %d A %d b %d w %d j %d p %d q %d K %d e %d",
        set_count('f'), set_count('i'), set_count('r'), set_count('T'), set_count('y'), set_count('A'), set_count('b'), set_count('w'),
        set_count('j'), set_count('p'), set_count('q'), set_count('K'), set_count('e'));
  for(const char *l = "AbwjfirTypqK"; *l; l++)
    CHECK(set_last(*l) == (*l == 'A' || *l == 'b' || *l == 'w' || *l == 'T' || *l == 'y'),
          "letter %c ends at %d, not its default", *l, set_last(*l));

  //---- paging and wrapping in Hardware
  menu_do(menu, MENU_EVENT_PGUP);
  CHECK(menu->entry == 10, "PGUP in Hardware: entry %d", menu->entry);
  CHECK_VISIBLE(menu);
  menu_do(menu, MENU_EVENT_PGUP);
  CHECK(menu->entry == 6, "PGUP again: entry %d", menu->entry);
  CHECK_VISIBLE(menu);
  menu_do(menu, MENU_EVENT_PGUP); menu_do(menu, MENU_EVENT_PGUP);
  CHECK(menu->entry == 1 && menu->offset == 0, "PGUP to the top: entry %d offset %d", menu->entry, menu->offset);
  menu_do(menu, MENU_EVENT_PGDOWN);
  CHECK(menu->entry == 5, "PGDOWN in Hardware: entry %d", menu->entry);
  CHECK_VISIBLE(menu);
  shot("hardware-page-2");
  menu_do(menu, MENU_EVENT_PGDOWN); menu_do(menu, MENU_EVENT_PGDOWN); menu_do(menu, MENU_EVENT_PGDOWN);
  CHECK(menu->entry == 14 && menu->offset == 10, "PGDOWN to the end: entry %d offset %d", menu->entry, menu->offset);
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 0 && menu->offset == 0, "DOWN past HDD prot.: entry %d offset %d, expected the title", menu->entry, menu->offset);
  menu_do(menu, MENU_EVENT_UP);
  CHECK(menu->entry == 14, "UP from the title: entry %d, expected 14", menu->entry);
  CHECK_VISIBLE(menu);
  for(int i=0;i<14;i++) { menu_do(menu, MENU_EVENT_UP); CHECK_VISIBLE(menu); }
  CHECK(menu->entry == 0 && menu->offset == 0, "UP to the title: entry %d offset %d", menu->entry, menu->offset);
  for(int i=0;i<14;i++) { menu_do(menu, MENU_EVENT_DOWN); CHECK_VISIBLE(menu); }
  CHECK(menu->entry == 14, "DOWN through Hardware: entry %d", menu->entry);

  //---- ESC closes the OSD; F12 opens it again on the same form
  menu_do(menu, MENU_EVENT_HIDE);
  CHECK(!osd_visible, "ESC left the OSD visible");
  menu_do(menu, MENU_EVENT_SHOW);
  CHECK(osd_visible && menu->form == 1 && menu->entry == 14, "after ESC and F12: form %d entry %d", menu->form, menu->entry);

  //---- the title returns to the entry that opened the form
  menu_do(menu, MENU_EVENT_DOWN);    // wraps to the title
  CHECK(menu->entry == 0, "Hardware title: entry %d", menu->entry);
  shot("hardware-title");
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 0 && menu->entry == 7, "back from Hardware: form %d entry %d, expected 0/7", menu->form, menu->entry);
  CHECK_VISIBLE(menu);
  shot("main-back");

  //---- About: a text page that scrolls and returns
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 8, "About entry %d", menu->entry);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == MENU_FORM_TEXT && menu->offset == 0, "About: form %d offset %d", menu->form, menu->offset);
  CHECK(menu_text_line(0) && !strncmp(menu_text_line(0), "PK8000 Nano", 11), "About shows '%s'", menu_text_line(0));
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
  CHECK(menu->form == 0 && menu->entry == 8, "back from About: form %d entry %d", menu->form, menu->entry);

  //---- Debug: a text page of the core's memcheck bytes (all zero here: sys_get_debug is stubbed)
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 9, "Debug entry %d", menu->entry);
  n = set_n;
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == MENU_FORM_TEXT && menu->offset == 0 && set_n == n, "Debug: form %d offset %d", menu->form, menu->offset);
  // the page must be the debug lines, not the About text: the label compare
  // in menu.c opened About for it on the third flash (4 Sep 2026)
  CHECK(menu_text_line(0) && !strncmp(menu_text_line(0), "por ", 4), "Debug shows '%s'", menu_text_line(0));
  shot("debug");
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 0 && menu->entry == 9, "back from Debug: form %d entry %d", menu->form, menu->entry);

  //---- Save settings is a button on the main form: it writes the card (fails here, no card)
  menu_do(menu, MENU_EVENT_PGDOWN);
  CHECK(menu->entry == 10 && menu->offset == 6, "Save settings entry %d offset %d", menu->entry, menu->offset);
  n = set_n;
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 0 && menu->entry == 10 && set_n == n && osd_visible, "Save settings left the main form or sent something");
  shot("main-end");
  menu_do(menu, MENU_EVENT_DOWN);    // the main form's title is not selectable: straight to Tape
  CHECK(menu->entry == 1 && menu->offset == 0, "DOWN past Save settings: entry %d offset %d, expected Tape", menu->entry, menu->offset);
  menu_do(menu, MENU_EVENT_UP);
  CHECK(menu->entry == 10 && menu->offset == 6, "UP from Tape: entry %d offset %d, expected Save settings", menu->entry, menu->offset);
  menu_do(menu, MENU_EVENT_HIDE);

  printf("menu-test: %d screens in %s, %d error(s)\n", shots, outdir, errors);
  return errors ? 1 : 0;
}
