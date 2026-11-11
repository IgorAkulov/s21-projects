CC = gcc
CFLAGS = -std=c11 -Wall -Wextra -Werror

TARGETS = s21_cat_GNU s21_cat_busybox

.PHONY: all clean rebuild

all: $(TARGETS)

s21_cat_GNU: s21_cat_GNU.c
	$(CC) $(CFLAGS) $< -o $@

s21_cat_busybox: s21_cat_busybox.c
	$(CC) $(CFLAGS) $< -o $@

clean:
	$(RM) $(TARGETS)

rebuild: clean
	$(MAKE) all
