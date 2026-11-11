#include <getopt.h>
#include <stdbool.h>
#include <stdio.h>

typedef struct {
  bool number_nonblank;
  bool show_ends;
  bool number;
  bool squeeze_blank;
  bool tabs;
  bool show_nonprinting;
} Flags;

typedef struct {
  int line_number;
  int prev;
  bool blank_printed;
  bool pending_cr;
  bool has_error;
} State;

bool apply_flag(int opt, Flags* flags) {
  bool status = false;

  switch (opt) {
    case 'n':
      flags->number = true;
      break;
    case 'b':
      flags->number_nonblank = true;
      break;
    case 's':
      flags->squeeze_blank = true;
      break;
    case 'v':
      flags->show_nonprinting = true;
      break;
    case 'e':
      flags->show_nonprinting = true;
      flags->show_ends = true;
      break;
    case 't':
      flags->show_nonprinting = true;
      flags->tabs = true;
      break;
    case 'E':
      flags->show_ends = true;
      break;
    case 'T':
      flags->tabs = true;
      break;
    case 'A':
      flags->show_nonprinting = true;
      flags->show_ends = true;
      flags->tabs = true;
      break;
    case 'u':
      break;
    case '?':
      fprintf(stderr, "Ошибка присвоения флага!\n");
      status = true;
      break;
  }

  return status;
}

void show_nonprinting_common(int ch) {
  if (ch < 32) {
    printf("^%c", ch + 64);
  } else if (ch > 31 && ch < 127) {
    putchar(ch);
  } else if (ch == 127) {
    printf("^?");
  }
}

bool show_nonprinting(int ch) {
  bool handled = false;
  if ((ch < 128) && (ch != '\n' && ch != '\t')) {
    handled = true;
    show_nonprinting_common(ch);
  } else if (ch > 127) {
    int last_seven = ch & 0x7F;
    printf("M-");
    show_nonprinting_common(last_seven);
    handled = true;
  }

  return handled;
}

bool squeeze_blank(int ch, bool* blank_line_printed, int* prev) {
  bool skip = false;
  if (ch != '\n') {
    *blank_line_printed = false;
  }
  if (*blank_line_printed == false && *prev == '\n' && ch == '\n') {
    *blank_line_printed = true;
  } else if (*blank_line_printed == true && *prev == '\n' && ch == '\n') {
    skip = true;
  }
  return skip;
}

void show_ends_cr(FILE* file, bool* pending_r) {
  int cr = fgetc(file);
  if (cr == '\n') {
    printf("^M");
    ungetc(cr, file);
  } else if (cr != EOF) {
    putchar('\r');
    ungetc(cr, file);
  } else {
    *pending_r = true;
  }
}

void print_number(int* linenumber) {
  printf("%6d\t", *linenumber);
  (*linenumber)++;
}

void process_cr(int ch, bool* cr_status) {
  if (*cr_status == true) {
    if (ch == '\n') {
      printf("^M");
    } else {
      putchar('\r');
    }
    *cr_status = false;
  }
}

void file_errors(FILE* file, bool* has_error) {
  if (ferror(file)) {
    *has_error = true;
  }
}

void print_character(int ch, const Flags* flags) {
  if (flags->show_ends && ch == '\n') {
    putchar('$');
  }

  if (!flags->show_nonprinting || !show_nonprinting(ch)) {
    if (flags->tabs && ch == '\t') {
      printf("^I");
    } else {
      putchar(ch);
    }
  }
}

void process_file_with_flags(FILE* file, const Flags* flags, State* st) {
  int ch;
  while ((ch = fgetc(file)) != EOF) {
    process_cr(ch, &st->pending_cr);
    if (flags->squeeze_blank &&
        squeeze_blank(ch, &st->blank_printed, &st->prev)) {
      continue;
    }
    if (flags->number && st->prev == '\n') {
      print_number(&st->line_number);
    }
    if (flags->number_nonblank && st->prev == '\n' && ch != '\n') {
      print_number(&st->line_number);
    }
    if (flags->show_ends && !flags->show_nonprinting && ch == '\r') {
      show_ends_cr(file, &st->pending_cr);
      st->prev = ch;
      continue;
    }
    print_character(ch, flags);
    st->prev = ch;
  }
  file_errors(file, &st->has_error);
}

bool process_with_flags(int argc, char* argv[], int name_indx,
                        const Flags* flags) {
  State st = {1, '\n', false, false, false};
  for (int i = name_indx; i < argc; i++) {
    FILE* file = fopen(argv[i], "r");
    if (file == NULL) {
      fprintf(stderr, "Ошибка открытия файла %s!\n", argv[i]);
      st.has_error = true;
      continue;
    }
    process_file_with_flags(file, flags, &st);
    fclose(file);
  }
  if (st.pending_cr) {
    putchar('\r');
  }

  return st.has_error;
}

bool set_flags(int argc, char* argv[], Flags* flags, int* indx,
               const struct option* longopts) {
  int opt;
  int opt_index = 0;
  opterr = 0;
  bool status = false;

  while (status == false && (opt = getopt_long(argc, argv, "nbsvetuETA",
                                               longopts, &opt_index)) != -1) {
    status = apply_flag(opt, flags);
  }
  *indx = optind;
  return status;
}

int main(int argc, char* argv[]) {
  if (argc < 2) {
    fprintf(stderr, "Не указано имя файла (не хватает аргументов)\n");
    return 1;
  }

  const struct option longopts[] = {
      {"number", no_argument, NULL, 'n'},
      {"number-nonblank", no_argument, NULL, 'b'},
      {"squeeze-blank", no_argument, NULL, 's'},
      {"show-nonprinting", no_argument, NULL, 'v'},
      {"show-all", no_argument, NULL, 'A'},
      {"show-ends", no_argument, NULL, 'E'},
      {"show-tabs", no_argument, NULL, 'T'},
      {NULL, 0, NULL, 0}};

  int filename_indx = 0;
  Flags flags = {false, false, false, false, false, false};
  bool status = set_flags(argc, argv, &flags, &filename_indx, longopts);
  if (status == false) {
    if (flags.number_nonblank) {
      flags.number = false;
    }
    status = process_with_flags(argc, argv, filename_indx, &flags);
  }
  return status;
}
