/*
 * litergss-shell.c
 *
 * The `ruby` executable of the Linux runtime: an empty shell, everything lives
 * in the library next to it (rpath $ORIGIN, see publish-kmp-desktop.sh).
 */

extern int litergss_main(int argc, char** argv);

int main(int argc, char** argv)
{
    return litergss_main(argc, argv);
}
