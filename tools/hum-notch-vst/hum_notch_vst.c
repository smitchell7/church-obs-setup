/* Hum Notch: a VST 2.x audio effect for OBS that removes mains hum.
 *
 * Four narrow notch filters (RBJ biquad, Q 30, about 2 Hz wide at 60 Hz) at 60, 120, 180 and 240 Hz on
 * each channel: the same filters as audio/hum-notch.conf. In OBS add it to the microphone source
 * (Filters > + > VST 2.x Plug-in > HumNotch) and turn it on and off with the eye icon. Its one setting,
 * Amount (default 100%), blends between the filtered and the plain sound.
 *
 * It must have at least one parameter: OBS saves a VST filter's settings by copying its parameter list
 * with &params[0], which aborts OBS (checked builds, e.g. the flatpak) when the list is empty.
 *
 * Written against the VST 2.4 binary interface directly (no SDK). Build and install with build.sh.
 */
#include <math.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define CHANNELS 2
#define NOTCHES 4
static const double FREQS[NOTCHES] = {60.0, 120.0, 180.0, 240.0};
static const double Q = 30.0;

/* --- The parts of the VST 2.4 interface used here --- */
typedef struct AEffect AEffect;
typedef intptr_t (*HostCallback)(AEffect *, int32_t, int32_t, intptr_t, void *, float);
typedef intptr_t (*DispatcherProc)(AEffect *, int32_t, int32_t, intptr_t, void *, float);
typedef void (*ProcessProc)(AEffect *, float **, float **, int32_t);
typedef void (*SetParameterProc)(AEffect *, int32_t, float);
typedef float (*GetParameterProc)(AEffect *, int32_t);

struct AEffect {
	int32_t magic;
	DispatcherProc dispatcher;
	ProcessProc process; /* deprecated accumulating process */
	SetParameterProc setParameter;
	GetParameterProc getParameter;
	int32_t numPrograms, numParams, numInputs, numOutputs, flags;
	intptr_t resvd1, resvd2;
	int32_t initialDelay, realQualities, offQualities;
	float ioRatio;
	void *object, *user;
	int32_t uniqueID, version;
	ProcessProc processReplacing;
	void *processDoubleReplacing;
	char future[56];
};

#define kEffectMagic 0x56737450 /* 'VstP' */
#define effFlagsCanReplacing (1 << 4)
enum {
	effOpen = 0, effClose = 1, effGetParamLabel = 6, effGetParamDisplay = 7, effGetParamName = 8, effSetSampleRate = 10, effSetBlockSize = 11,
	effMainsChanged = 12, effGetPlugCategory = 35, effGetEffectName = 45, effGetVendorString = 47,
	effGetProductString = 48, effGetVendorVersion = 49, effCanDo = 51, effGetVstVersion = 58,
};
#define kPlugCategEffect 1

/* --- The filter --- */
typedef struct { double b0, b1, b2, a1, a2; } Coeffs;
typedef struct { double z1, z2; } State;
typedef struct {
	AEffect effect;
	double rate;
	float strength; /* "Amount", 0..1: 1 = full notch, 0 = no effect */
	Coeffs c[NOTCHES];
	State s[CHANNELS][NOTCHES];
} Plugin;

static void set_rate(Plugin *p, double rate)
{
	p->rate = rate > 0 ? rate : 48000.0;
	for (int n = 0; n < NOTCHES; n++) {
		double w = 2.0 * M_PI * FREQS[n] / p->rate, alpha = sin(w) / (2.0 * Q), a0 = 1.0 + alpha;
		p->c[n] = (Coeffs){1.0 / a0, -2.0 * cos(w) / a0, 1.0 / a0, -2.0 * cos(w) / a0, (1.0 - alpha) / a0};
	}
	memset(p->s, 0, sizeof p->s);
}

static float filter(Plugin *p, int ch, float in)
{
	double x = in;
	for (int n = 0; n < NOTCHES; n++) { /* transposed direct form II */
		Coeffs *c = &p->c[n];
		State *s = &p->s[ch][n];
		double y = c->b0 * x + s->z1;
		s->z1 = c->b1 * x - c->a1 * y + s->z2;
		s->z2 = c->b2 * x - c->a2 * y;
		x = y;
	}
	/* Keep the state out of denormal numbers (slow) when the input goes silent. */
	for (int n = 0; n < NOTCHES; n++) {
		if (fabs(p->s[ch][n].z1) < 1e-30) p->s[ch][n].z1 = 0;
		if (fabs(p->s[ch][n].z2) < 1e-30) p->s[ch][n].z2 = 0;
	}
	return (float)x;
}

static void process_replacing(AEffect *e, float **in, float **out, int32_t frames)
{
	Plugin *p = (Plugin *)e;
	double k = p->strength;
	for (int ch = 0; ch < CHANNELS; ch++)
		for (int32_t i = 0; i < frames; i++) {
			float x = in[ch][i];
			out[ch][i] = (float)(x + k * (filter(p, ch, x) - x));
		}
}

static void process_accumulating(AEffect *e, float **in, float **out, int32_t frames)
{
	Plugin *p = (Plugin *)e;
	double k = p->strength;
	for (int ch = 0; ch < CHANNELS; ch++)
		for (int32_t i = 0; i < frames; i++) {
			float x = in[ch][i];
			out[ch][i] += (float)(x + k * (filter(p, ch, x) - x));
		}
}

static void set_parameter(AEffect *e, int32_t i, float v)
{
	if (i == 0) ((Plugin *)e)->strength = v < 0 ? 0 : v > 1 ? 1 : v;
}
static float get_parameter(AEffect *e, int32_t i) { return i == 0 ? ((Plugin *)e)->strength : 0.0f; }

static intptr_t copy_str(void *dst, const char *s, size_t max)
{
	if (!dst) return 0;
	strncpy((char *)dst, s, max - 1);
	((char *)dst)[max - 1] = 0;
	return 1;
}

static intptr_t dispatcher(AEffect *e, int32_t op, int32_t index, intptr_t value, void *ptr, float opt)
{
	Plugin *p = (Plugin *)e;
	(void)index; (void)value;
	switch (op) {
	case effClose: free(p); return 1;
	case effSetSampleRate: set_rate(p, opt); return 1;
	case effMainsChanged: memset(p->s, 0, sizeof p->s); return 1;
	case effGetParamName: return index == 0 ? copy_str(ptr, "Amount", 8) : 0;
	case effGetParamLabel: return index == 0 ? copy_str(ptr, "%", 8) : 0;
	case effGetParamDisplay:
		if (index != 0 || !ptr) return 0;
		snprintf((char *)ptr, 8, "%d", (int)(p->strength * 100 + 0.5f));
		return 1;
	case effGetPlugCategory: return kPlugCategEffect;
	case effGetEffectName: return copy_str(ptr, "Hum Notch", 32);
	case effGetProductString: return copy_str(ptr, "Hum Notch 60/120/180/240 Hz", 64);
	case effGetVendorString: return copy_str(ptr, "church-obs-setup", 64);
	case effGetVendorVersion: return 1000;
	case effGetVstVersion: return 2400;
	case effCanDo: return ptr && !strcmp((const char *)ptr, "plugAsChannelInsert") ? 1 : 0;
	default: return 0;
	}
}

__attribute__((visibility("default"))) AEffect *VSTPluginMain(HostCallback host)
{
	(void)host;
	Plugin *p = calloc(1, sizeof *p);
	if (!p) return NULL;
	AEffect *e = &p->effect;
	e->magic = kEffectMagic;
	e->dispatcher = dispatcher;
	e->process = process_accumulating;
	e->processReplacing = process_replacing;
	e->setParameter = set_parameter;
	e->getParameter = get_parameter;
	e->numParams = 1;
	e->numInputs = e->numOutputs = CHANNELS;
	e->flags = effFlagsCanReplacing;
	e->uniqueID = 0x48756d4e; /* 'HumN' */
	e->version = 1000;
	e->object = p;
	p->strength = 1.0f;
	set_rate(p, 48000.0);
	return e;
}

/* Older Linux VST hosts look for "main". */
__attribute__((visibility("default"))) AEffect *main_plugin(HostCallback host) __asm__("main");
AEffect *main_plugin(HostCallback host) { return VSTPluginMain(host); }
