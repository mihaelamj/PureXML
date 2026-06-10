/* libxml2 side of the PureXML benchmark (scripts/benchmark.sh).
 * Times the same operations the Swift driver times, over the same file,
 * with internal timing so process startup never taints a number.
 * Output: CSV lines "library,operation,bytes,seconds".
 */
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/xpath.h>
#include <stdio.h>
#include <string.h>
#include <sys/time.h>

static double now(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (double)tv.tv_sec + (double)tv.tv_usec / 1e6;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: bench-libxml2 <file.xml> <iterations>\n");
        return 1;
    }
    const char *path = argv[1];
    int iterations = atoi(argv[2]);
    xmlInitParser();

    /* Read the bytes once so parse timing excludes IO. */
    FILE *f = fopen(path, "rb");
    if (!f) { perror("open"); return 1; }
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buffer = malloc((size_t)size);
    fread(buffer, 1, (size_t)size, f);
    fclose(f);

    /* Parse. */
    double best_parse = 1e9;
    xmlDocPtr doc = NULL;
    for (int i = 0; i < iterations; i++) {
        if (doc) xmlFreeDoc(doc);
        double t0 = now();
        doc = xmlReadMemory(buffer, (int)size, path, NULL, XML_PARSE_NONET);
        double dt = now() - t0;
        if (dt < best_parse) best_parse = dt;
    }
    if (!doc) { fprintf(stderr, "parse failed\n"); return 1; }
    printf("libxml2,parse,%ld,%.6f\n", size, best_parse);

    /* Serialize. */
    double best_serialize = 1e9;
    for (int i = 0; i < iterations; i++) {
        xmlChar *out = NULL;
        int outLen = 0;
        double t0 = now();
        xmlDocDumpMemory(doc, &out, &outLen);
        double dt = now() - t0;
        if (dt < best_serialize) best_serialize = dt;
        xmlFree(out);
    }
    printf("libxml2,serialize,%ld,%.6f\n", size, best_serialize);

    /* XPath: count a broad selection. */
    double best_xpath = 1e9;
    long count = 0;
    for (int i = 0; i < iterations; i++) {
        double t0 = now();
        xmlXPathContextPtr ctx = xmlXPathNewContext(doc);
        xmlXPathObjectPtr res = xmlXPathEvalExpression((const xmlChar *)"count(//item[@kind='even'])", ctx);
        count = (long)res->floatval;
        double dt = now() - t0;
        if (dt < best_xpath) best_xpath = dt;
        xmlXPathFreeObject(res);
        xmlXPathFreeContext(ctx);
    }
    printf("libxml2,xpath,%ld,%.6f\n", size, best_xpath);
    fprintf(stderr, "libxml2 xpath count: %ld\n", count);

    xmlFreeDoc(doc);
    xmlCleanupParser();
    free(buffer);
    return 0;
}
