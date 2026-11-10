/* vkspv_sg32_emulate (#40: AMD's GCN has only 64-lane subgroups): NVN's subgroup code made to act on 32-lane halves, as NVN's warps. The rewrite of
   test_sg32.comp (the lane index, a shuffle, a ballot, the LtMask, Any, All), of test_sg32_vote.comp (Any and All without a lane index: the rewrite declares
   one) and of test_sg32_bcast.comp (an operation it does not handle: left as it is), checked on the words. On a GPU the rewritten shaders give what 32-lane
   warps give (a CPU model of them) whatever the GPU's subgroup size, and on 32-lane subgroups exactly what the shaders as compiled give. NXRT_TEST_CORPUS
   (nxrt.vk_sg32_corpus): every module of real shader caches that uses subgroups is rewritten and made into a module, the compute ones into pipelines, with
   validation on. The GPU part is skipped without a device. */
#include "vk_test.h"
#include "vk_shader.h"
#include "vk_pipe.h"
#include "test_sg32_comp.h"
#include "test_sg32_vote_comp.h"
#include "test_sg32_bcast_comp.h"
#ifdef _WIN32
#include <windows.h>
#else
#include <dirent.h>
#endif

NXRT_EARLY_RESERVE()

enum { OP_ENTRY_POINT = 15, OP_DECORATE = 71, OP_ALL = 334, OP_ANY = 335, OP_BCAST_FIRST = 338, OP_BALLOT = 339, OP_SHUFFLE = 345, SENTINEL = 0xdeadbeefu };
static int count_op(const uint32_t *w, size_t n, uint32_t op) { int c = 0; for (size_t i = 5; i < n && (w[i] >> 16); i += w[i] >> 16) c += (w[i] & 0xffff) == op; return c; }
static int count_builtin(const uint32_t *w, size_t n, uint32_t b) {
    int c = 0; for (size_t i = 5; i < n && (w[i] >> 16); i += w[i] >> 16) c += (w[i] & 0xffff) == OP_DECORATE && (w[i] >> 16) == 4 && w[i + 2] == 11 && w[i + 3] == b; return c;
}
static uint32_t entry_words(const uint32_t *w, size_t n) { for (size_t i = 5; i < n && (w[i] >> 16); i += w[i] >> 16) if ((w[i] & 0xffff) == OP_ENTRY_POINT) return w[i] >> 16; return 0; }
static int uses_subgroups(const uint32_t *w, size_t n) {
    return count_op(w, n, OP_ALL) || count_op(w, n, OP_ANY) || count_op(w, n, OP_BALLOT) || count_op(w, n, OP_SHUFFLE);
}
static uint32_t *copy_words(const uint32_t *w, size_t n) { uint32_t *c = malloc(n * 4); memcpy(c, w, n * 4); return c; }

// What 32-lane warps give (NVN's): each 32 invocations of a 64-invocation group one warp; a lane whose value is 7 leaves before the ballot and the votes
static void model(const uint32_t *x, uint32_t lanes, uint32_t *o, int vote) {
    for (uint32_t base = 0; base < lanes; base += 32) {
        uint32_t ball = 0; int any = 0, all = 1, any0 = 0, all3 = 1;
        for (uint32_t l = 0; l < 32; l++) { uint32_t v = x[base + l]; if (v == 7) continue;
            ball |= (v & 1u) << l; any |= v > 5; all &= v < 6; any0 |= v == 0; all3 &= v != 3; }
        for (uint32_t l = 0; l < 32; l++) {
            uint32_t i = base + l, v = x[i];
            if (vote) { o[i * 2] = v == 7 ? SENTINEL : (uint32_t)any0; o[i * 2 + 1] = v == 7 ? SENTINEL : (uint32_t)all3; continue; }
            uint32_t src = (l + v) & 31u;
            o[i * 6] = l; o[i * 6 + 1] = x[base + src] * 3u + src;
            if (v == 7) { o[i * 6 + 2] = o[i * 6 + 3] = o[i * 6 + 4] = o[i * 6 + 5] = SENTINEL; continue; }
            o[i * 6 + 2] = ball; o[i * 6 + 3] = (uint32_t)__builtin_popcount(ball & ((1u << l) - 1u)); o[i * 6 + 4] = (uint32_t)any; o[i * 6 + 5] = (uint32_t)all;
        }
    }
}

// One dispatch of groups x 64 invocations over x; out (outs words a lane, SENTINEL first) after it. 1 when it ran
static int run(const uint32_t *words, size_t n, const uint32_t *x, uint32_t groups, uint32_t outs, uint32_t *out) {
    uint32_t lanes = groups * 64; int ok = 0;
    VkBuffer buf[2] = {0}; vk_alloc mem[2] = {0}; VkDeviceSize size[2] = {(VkDeviceSize)lanes * 4, (VkDeviceSize)lanes * outs * 4};
    for (int k = 0; k < 2; k++) {
        VkBufferCreateInfo bci = {VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, NULL, 0, size[k], VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, VK_SHARING_MODE_EXCLUSIVE, 0, NULL};
        if (vkCreateBuffer(g_vk.dev, &bci, NULL, &buf[k])) return 0;
        VkMemoryRequirements mr; vkGetBufferMemoryRequirements(g_vk.dev, buf[k], &mr);
        if (vk_alloc_mem(&mr, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, 0, &mem[k]) || !mem[k].map) return 0;
        vkBindBufferMemory(g_vk.dev, buf[k], mem[k].mem, mem[k].off);
    }
    memcpy(mem[0].map, x, (size_t)lanes * 4);
    for (uint32_t i = 0; i < lanes * outs; i++) ((uint32_t *)mem[1].map)[i] = SENTINEL;
    VkDescriptorSetLayoutBinding b[2] = {{0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, NULL}, {1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT, NULL}};
    VkDescriptorSetLayoutCreateInfo dl = {VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, NULL, 0, 2, b};
    VkDescriptorSetLayout dsl; VkPipelineLayout pl; VkShaderModule m; VkPipeline p; VkDescriptorPool dp; VkDescriptorSet ds;
    vkCreateDescriptorSetLayout(g_vk.dev, &dl, NULL, &dsl);
    VkPipelineLayoutCreateInfo pli = {VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, NULL, 0, 1, &dsl, 0, NULL};
    vkCreatePipelineLayout(g_vk.dev, &pli, NULL, &pl);
    VkShaderModuleCreateInfo mi = {VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, NULL, 0, n * 4, words};
    if (vkCreateShaderModule(g_vk.dev, &mi, NULL, &m)) return 0;
    VkComputePipelineCreateInfo ci = {VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO, NULL, 0,
                                      {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, NULL, 0, VK_SHADER_STAGE_COMPUTE_BIT, m, "main", NULL}, pl, VK_NULL_HANDLE, -1};
    if (vkCreateComputePipelines(g_vk.dev, VK_NULL_HANDLE, 1, &ci, NULL, &p)) return 0;
    VkDescriptorPoolSize ps = {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 2};
    VkDescriptorPoolCreateInfo dpi = {VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, NULL, 0, 1, 1, &ps};
    vkCreateDescriptorPool(g_vk.dev, &dpi, NULL, &dp);
    VkDescriptorSetAllocateInfo ai = {VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, NULL, dp, 1, &dsl};
    vkAllocateDescriptorSets(g_vk.dev, &ai, &ds);
    VkDescriptorBufferInfo bi[2] = {{buf[0], 0, size[0]}, {buf[1], 0, size[1]}};
    VkWriteDescriptorSet wr[2] = {{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, NULL, ds, 0, 0, 1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, NULL, &bi[0], NULL},
                                  {VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, NULL, ds, 1, 0, 1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, NULL, &bi[1], NULL}};
    vkUpdateDescriptorSets(g_vk.dev, 2, wr, 0, NULL);
    VkCommandBuffer cb = vk_once_begin();
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, p);
    vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pl, 0, 1, &ds, 0, NULL);
    vkCmdDispatch(cb, groups, 1, 1);
    vk_mem_barrier(cb, VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, VK_ACCESS_2_SHADER_WRITE_BIT, VK_PIPELINE_STAGE_2_HOST_BIT, VK_ACCESS_2_HOST_READ_BIT);
    if (!vk_once_end(cb)) { memcpy(out, mem[1].map, (size_t)lanes * outs * 4); ok = 1; }
    vkDestroyPipeline(g_vk.dev, p, NULL); vkDestroyShaderModule(g_vk.dev, m, NULL); vkDestroyDescriptorPool(g_vk.dev, dp, NULL);
    vkDestroyPipelineLayout(g_vk.dev, pl, NULL); vkDestroyDescriptorSetLayout(g_vk.dev, dsl, NULL);
    for (int k = 0; k < 2; k++) { vkDestroyBuffer(g_vk.dev, buf[k], NULL); vk_free_mem(&mem[k]); }
    return ok;
}
static int differ(const uint32_t *a, const uint32_t *b, uint32_t n) { int d = 0; for (uint32_t i = 0; i < n; i++) d += a[i] != b[i]; return d; }

static void *read_all(const char *path, long *size) {
    FILE *f = fopen(path, "rb"); if (!f) return NULL;
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    void *p = n > 0 ? malloc(n) : NULL;
    if (!p || fread(p, 1, n, f) != (size_t)n) { free(p); p = NULL; }
    fclose(f); *size = n; return p;
}
// The corpus part: each module of a shader cache's vk/ that uses subgroups, rewritten (all of it: nothing left for 64 lanes), made into a module with
// validation on (no messages of its own beyond the translation's), and through vksh_make with the rewrite on; the compute ones into pipelines
static int corpus_dir(const char *d) {
    static char keys[8192][17]; char pat[1200]; int nk = 0;
#ifdef _WIN32
    snprintf(pat, sizeof pat, "%s/vk/*.spv", d);
    WIN32_FIND_DATAA fd; HANDLE h = FindFirstFileA(pat, &fd);
    if (h == INVALID_HANDLE_VALUE) return 0;
    do { if (strlen(fd.cFileName) == 20 && nk < 8192) { memcpy(keys[nk], fd.cFileName, 16); keys[nk++][16] = 0; } } while (FindNextFileA(h, &fd));
    FindClose(h);
#else
    snprintf(pat, sizeof pat, "%s/vk", d);
    DIR *dir = opendir(pat); if (!dir) return 0;
    for (struct dirent *e; (e = readdir(dir));) { size_t l = strlen(e->d_name); if (l == 20 && !strcmp(e->d_name + 16, ".spv") && nk < 8192) { memcpy(keys[nk], e->d_name, 16); keys[nk++][16] = 0; } }
    closedir(dir);
#endif
    int users = 0, done = 0, pipes = 0, cs = 0; uint32_t own = 0;
    g_vk.has.sg32_emulate = 1;
    for (int k = 0; k < nk; k++) {
        char ps[1300], pj[1300]; snprintf(ps, sizeof ps, "%s/vk/%s.spv", d, keys[k]); snprintf(pj, sizeof pj, "%s/vk/%s.json", d, keys[k]);
        long ns = 0, nj = 0; uint32_t *spv = read_all(ps, &ns); char *js = read_all(pj, &nj);
        if (spv && js && ns > 20 && uses_subgroups(spv, (size_t)ns / 4)) {
            users++;
            uint32_t e0 = atomic_load(&g_vk.val_errors); VkShaderModule m = VK_NULL_HANDLE;
            VkShaderModuleCreateInfo mi = {VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, NULL, 0, (size_t)ns, spv};
            vkCreateShaderModule(g_vk.dev, &mi, NULL, &m); if (m) vkDestroyShaderModule(g_vk.dev, m, NULL);
            uint32_t e1 = atomic_load(&g_vk.val_errors);
            uint32_t *w = copy_words(spv, (size_t)ns / 4); int r = 0; const char *why = NULL;
            size_t rn = vkspv_sg32_emulate(&w, (size_t)ns / 4, &r, &why);
            CHECK(r > 0 && !why && !count_op(w, rn, OP_ANY) && !count_op(w, rn, OP_ALL), "corpus %s: %s rewritten (%d instructions%s%s)", d, keys[k], r,
                  why ? ": " : "", why ? why : "");
            done += r > 0 && !why;
            m = VK_NULL_HANDLE; mi.codeSize = rn * 4; mi.pCode = w;
            vkCreateShaderModule(g_vk.dev, &mi, NULL, &m); if (m) vkDestroyShaderModule(g_vk.dev, m, NULL);
            uint32_t e2 = atomic_load(&g_vk.val_errors);
            const char *mwhy = NULL; VkPipelineLayout pl = VK_NULL_HANDLE;
            vks_shader *s = vksh_make(keys[k], (const uint8_t *)spv, (size_t)ns, js, (size_t)nj, &mwhy);
            CHECK(m != VK_NULL_HANDLE && s, "corpus %s: %s's rewritten module made (%s)", d, keys[k], mwhy ? mwhy : "ok");
            if (s && s->stage == VKS_CS) { cs++; VkPipeline p = vkp_compute(s, &pl); pipes += p != VK_NULL_HANDLE; CHECK(p != VK_NULL_HANDLE, "corpus %s: %s's compute pipeline made", d, keys[k]); }
            uint32_t e3 = atomic_load(&g_vk.val_errors);
            CHECK(e2 - e1 <= e1 - e0 && e3 - e2 <= e1 - e0, "corpus %s: %s: no validation errors of the rewrite's own (rewritten %u, made %u; the translation as it is %u)",
                  d, keys[k], e2 - e1, e3 - e2, e1 - e0);
            own += e1 - e0;
            free(w);
        }
        free(spv); free(js);
    }
    g_vk.has.sg32_emulate = 0;
    printf("corpus %s: %d modules, %d use subgroups, %d rewritten, %d of %d compute pipelines made (%u validation errors from the translations as they are)\n",
           d, nk, users, done, pipes, cs, own);
    return nk > 0;
}

int main(void) {
    crash_install();
    // test_sg32.comp: every operation NVN's translations use, rewritten
    size_t n = sizeof test_sg32_comp_spv / 4; uint32_t *w = copy_words(test_sg32_comp_spv, n); int r = -1; const char *why = "unset";
    int b0 = count_op(w, n, OP_BALLOT), any0 = count_op(w, n, OP_ANY), all0 = count_op(w, n, OP_ALL), sh0 = count_op(w, n, OP_SHUFFLE);
    CHECK(b0 == 1 && any0 == 1 && all0 == 1 && sh0 == 1 && count_builtin(w, n, 41) == 1 && count_builtin(w, n, 4420) == 1,
          "the test shader has a ballot, Any, All, a shuffle, the lane index and the LtMask");
    size_t rn = vkspv_sg32_emulate(&w, n, &r, &why);
    CHECK(rn > n && !why && r >= 6, "rewritten: %d instructions, %zu -> %zu words", r, n, rn);
    CHECK(count_op(w, rn, OP_ANY) == 0 && count_op(w, rn, OP_ALL) == 0 && count_op(w, rn, OP_BALLOT) == b0 + any0 + 2 * all0 && count_op(w, rn, OP_SHUFFLE) == sh0,
          "Any and All made from ballots, the ballot and the shuffle kept (%d ballots)", count_op(w, rn, OP_BALLOT));
    CHECK(w[3] > test_sg32_comp_spv[3] && count_builtin(w, rn, 41) == 1 && entry_words(w, rn) == entry_words(test_sg32_comp_spv, n),
          "the id bound grows (%u -> %u), the lane index is the module's own", test_sg32_comp_spv[3], w[3]);
    // test_sg32_vote.comp: no lane index of its own: declared, and named by the entry point
    size_t vn = sizeof test_sg32_vote_comp_spv / 4; uint32_t *v = copy_words(test_sg32_vote_comp_spv, vn); int vr = -1;
    CHECK(count_builtin(v, vn, 41) == 0, "the vote shader has no lane index");
    size_t vrn = vkspv_sg32_emulate(&v, vn, &vr, &why);
    CHECK(vrn > vn && !why && vr == 2 && count_builtin(v, vrn, 41) == 1 && entry_words(v, vrn) == entry_words(test_sg32_vote_comp_spv, vn) + 1 &&
          count_op(v, vrn, OP_ANY) == 0 && count_op(v, vrn, OP_ALL) == 0, "Any and All rewritten, a lane index declared and in the entry point's interface");
    // test_sg32_bcast.comp: an operation the rewrite does not handle: left as it is, with the reason
    size_t cn = sizeof test_sg32_bcast_comp_spv / 4; uint32_t *c = copy_words(test_sg32_bcast_comp_spv, cn); int cr = -1; why = NULL;
    CHECK(count_op(c, cn, OP_BCAST_FIRST) == 1 && vkspv_sg32_emulate(&c, cn, &cr, &why) == cn && cr == 0 && why && !memcmp(c, test_sg32_bcast_comp_spv, cn * 4),
          "a broadcast is left as it is (%s)", why ? why : "no reason");
    free(c);
    // where: subgroups of 64 lanes or that may have 64 (AMD), not 32 (NVIDIA) or at most 32 (Intel); NXRT_VK_SUBGROUP32=0 never, =emulate on any GPU
    CHECK(vkspv_sg32_emulate_wanted(64, 64, NULL) && vkspv_sg32_emulate_wanted(64, 0, NULL) && vkspv_sg32_emulate_wanted(32, 64, NULL) &&
          !vkspv_sg32_emulate_wanted(32, 32, NULL) && !vkspv_sg32_emulate_wanted(16, 32, NULL) && !vkspv_sg32_emulate_wanted(32, 0, NULL),
          "the rewrite where subgroups may have 64 lanes, not where they have 32 or fewer");
    CHECK(!vkspv_sg32_emulate_wanted(64, 64, "0") && vkspv_sg32_emulate_wanted(32, 32, "emulate") && vkspv_sg32_emulate_wanted(64, 64, "1") &&
          !vkspv_sg32_emulate_wanted(32, 32, "1"), "NXRT_VK_SUBGROUP32: 0 never, emulate on any GPU, 1 as unset");

    // on a GPU: what 32-lane warps give, whatever this GPU's subgroups
    int corpus_none = 0, rc = vt_up(0, 1);
    if (rc == 0) {
        enum { GROUPS = 16, LANES = GROUPS * 64 };
        static uint32_t x[LANES], want[LANES * 6], got[LANES * 6], orig[LANES * 6];
        for (int i = 0; i < LANES; i++) x[i] = vt_rand() % 8;   // the 7s leave early
        x[3] = x[40] = 7; x[70] = 6; x[100] = 0;   // a lane that leaves, an Any that holds, an All that does not, in some warps at least
        uint32_t sgs = g_vk.has.subgroup_size;
        if (sgs < 32) {   // lavapipe's 8, some Intel GPUs: a subgroup holds less than a warp, so no 32-lane result to check (the runtime leaves the rewrite off there)
            printf("subgroups of %u lanes on %s, fewer than a 32-lane warp: the GPU part and the corpus part are skipped (docs/subgroup-halves.md)\n",
                   sgs, g_vk.props.deviceName);
            vt_down(0); free(w); free(v);
            printf("%s: %d checks, %d failed\n", g_fail ? "FAIL" : "ok", g_checks, g_fail);
            return g_fail ? 1 : 77;
        }
        model(x, LANES, want, 0);
        CHECK(run(w, rn, x, GROUPS, 6, got), "the rewritten shader ran");
        int d = differ(got, want, LANES * 6);
        CHECK(d == 0, "the rewritten shader gives what 32-lane warps give on this GPU's %u-lane subgroups (%d of %d values differ)", sgs, d, LANES * 6);
        CHECK(run((const uint32_t *)test_sg32_comp_spv, n, x, GROUPS, 6, orig), "the shader as compiled ran");
        int od = differ(orig, want, LANES * 6);
        if (sgs == 32) CHECK(od == 0 && !memcmp(orig, got, sizeof got), "on 32-lane subgroups the rewritten shader gives exactly what the shader as compiled gives");
        else printf("the shader as compiled on %u-lane subgroups: %d of %d values differ from 32-lane warps (what the rewrite is for)\n", sgs, od, LANES * 6);
        model(x, LANES, want, 1);
        CHECK(run(v, vrn, x, GROUPS, 2, got), "the rewritten vote shader ran");
        d = differ(got, want, LANES * 2);
        CHECK(d == 0, "the rewritten vote shader gives what 32-lane warps give (%d of %d values differ)", d, LANES * 2);
        CHECK(run((const uint32_t *)test_sg32_vote_comp_spv, vn, x, GROUPS, 2, orig), "the vote shader as compiled ran");
        if (sgs == 32) CHECK(!memcmp(orig, got, (size_t)LANES * 2 * 4), "on 32-lane subgroups the rewritten vote shader gives exactly what it gave");
        printf("subgroups of %u lanes on %s\n", sgs, g_vk.props.deviceName);
        const char *cl = getenv("NXRT_TEST_CORPUS");   // nxrt.vk_sg32_corpus: the subgroup modules of real shader caches
        if (cl && *cl) {
            char dirs[4096]; snprintf(dirs, sizeof dirs, "%s", cl); int found = 0;
            for (char *dd = strtok(dirs, "|"); dd; dd = strtok(NULL, "|")) found += corpus_dir(dd);
            printf("corpus: %d shader cache%s checked\n", found, found == 1 ? "" : "s");
            corpus_none = !found;
        }
        uint32_t verr = atomic_load(&g_vk.val_errors);
        CHECK(verr == 0 || cl, "no validation errors (%u)", verr);
        vt_down(0);
    } else if (rc == 77) printf("no GPU: the GPU part skipped\n");
    else return 1;
    free(w); free(v);
    printf("%s: %d checks, %d failed\n", g_fail ? "FAIL" : "ok", g_checks, g_fail);
    if (corpus_none && !g_fail) { printf("no shader cache of NXRT_TEST_CORPUS found: skipped\n"); return 77; }
    return g_fail ? 1 : 0;
}
