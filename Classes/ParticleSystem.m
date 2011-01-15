//
//  ParticleSystem.m
//  particleDemo
//
//  Created by Tim Omernick on 5/20/09.
//  Copyright 2009 ngmoco:). All rights reserved.
//

/*
--------

Copyright (c) 2009, ngmoco, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

   * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
   * Neither the name of ngmoco, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#import "ParticleSystem.h"

#import <OpenGLES/ES1/gl.h>

#import "GLTexture.h"

#define MAX_VERTS (20000)
#define ARRAY_SIZE (MAX_VERTS + 6)
#define NUM_TEXTURES (2)

typedef struct _ParticleVert
{
    short v[2];
    unsigned color;
    float uv[2];
} ParticleVert;

static ParticleVert _interleavedVerts[MAX_VERTS];

static GLTexture *_particleTexture = nil;

#define MAX_PARTICLES (20000)
static Particle _particlePool[MAX_PARTICLES];
static unsigned _firstFreeParticle = 0;
static unsigned _vertexCount = 0;

static Particle *_particleAlloc()
{
    // Don't malloc() during a game -- pre-alloate pools of objects.  Make use of ring buffers.  Just don't allocate any memory!
    Particle *particle = &_particlePool[_firstFreeParticle];
    _firstFreeParticle++;
    if (_firstFreeParticle >= MAX_PARTICLES)
        _firstFreeParticle = 0;

    return particle;
}

static void _particleFree(Particle *particle)
{
    // No need... see above
}

enum { H, S, V };

void _HSVToRGB(const float *HSV, unsigned char *RGB)
{
    float h = HSV[H], s = HSV[S], v = HSV[V];
    float w = roundf(h) / 60.0f;
    float h1 = fmodf(floorf(w), 6.0f);
    float f = w - floorf(w);
    float p = v * (1.0f - s);
    float q = v * (1.0f - (f * s));
    float t = v * (1.0f - ((1.0f - f) * s));
    
    p *= 255.0f;
    q *= 255.0f;
    t *= 255.0f;
    v *= 255.0f;
    
    switch ((int)h1) {
        case 0:
            RGB[0] = v;
            RGB[1] = t;
            RGB[2] = p;
        break;
        
        case 1:
            RGB[0] = q;
            RGB[1] = v;
            RGB[2] = p;
        break;

        case 2:
            RGB[0] = p;
            RGB[1] = v;
            RGB[2] = t;
        break;

        case 3:
            RGB[0] = p;
            RGB[1] = q;
            RGB[2] = v;
        break;

        case 4:
            RGB[0] = t;
            RGB[1] = p;
            RGB[2] = v;
        break;

        case 5:
            RGB[0] = v;
            RGB[1] = p;
            RGB[2] = q;
        break;
        
        default:
            RGB[0] = RGB[1] = RGB[2] = 0.0f;
            NSLog(@"um that's not a color");
        break;
    }
}

@implementation ParticleSystem

- (id)init
{
    if (!(self = [super init]))
        return nil;
        
    _hueCycle = (random() % 360);
    
    return self;
}

- (void)dealloc
{
    [self reset];
    
    [super dealloc];
}

- (void)_emitParticleAtTime:(double)time x:(float)x y:(float)y push:(BOOL)push
{
    Particle *particle = _particleAlloc();
  
    particle->next = NULL;
    particle->prev = NULL;
    
    if (!_firstParticle) {
      // First particle
      _firstParticle = particle;
    } else if (!_lastParticle) {
      // Second particle (special case because it's also the last)
      _lastParticle = particle;
      _lastParticle->prev = _firstParticle;
      _firstParticle->next = _lastParticle;
    } else if (particle == _firstParticle) {
      _lastParticle = NULL;
    } else {
      // Last particle
      _lastParticle->next = particle;
      particle->prev = _lastParticle;
      _lastParticle = particle;
    }
    
    particle->x = x;
    particle->y = y;
    float angle = (random() % 360) * (M_PI / 180.0f);
    float scale = 30 + (random() % 120);
    particle->velocityX = cosf(angle) * scale;
    particle->velocityY = sinf(angle) * scale;
    if (push)
        particle->velocityY -= 30 + (random() % 30);
    particle->birth = time;
    particle->alpha = 1.0f;
    particle->size = 0.0f;
    particle->hue = _hueCycle;
    particle->rotation = (random() % 360) * (M_PI / 180.0f);
    particle->texture = random() % NUM_TEXTURES;
    
    _lastEmitTime = time;
}

- (void)_freeParticle:(Particle *)particle
{
    Particle *prev = particle->prev;
    Particle *next = particle->next;
    
    if (prev)
        prev->next = next;
    if (next)
        next->prev = prev;
        
    if (particle == _firstParticle)
        _firstParticle = next;
    else if (particle == _lastParticle)
        _lastParticle = prev;
}

- (BOOL)animate:(double)time
{
    // time elapsed
    if (_lastTime == 0.0) {
        _lastTime = time;
        _birth = time;
    }
    double step = time - _lastTime;
    _lastTime = time;
            
    // emit particles
    if (!_decay) {
        // emission rate
        static const float emissionRate = 0.1f;
        if (_lastEmitTime == 0.0)
            _lastEmitTime = time - emissionRate;
            
        // emit at a fixed interval
        if (_birth == time || time - _lastEmitTime >= emissionRate) {
            unsigned count;
            BOOL push;
            if (_birth == time) {
                count = 40;
                push = YES;
            } else {
                count = 1;
                push = NO;
            }
            
            for (unsigned i = 0; i < count; i++) {
                [self _emitParticleAtTime:time x:_location.x y:_location.y push:push];
            }
        }
    }
    
    // animate particles
    Particle *particle = _firstParticle;
    unsigned particleCount = 0;
    while (particle) {
        // gravity
        static const float gravity = 120.0f;
        particle->velocityY += gravity * step;

        // velocity
        float dx = particle->velocityX * step;
        float dy = particle->velocityY * step;
        particle->x += dx;
        particle->y += dy;

        // fall off bottom of screen
        if (particle->y > 500) {
            Particle *dead = particle;
            particle = particle->next;
            [self _freeParticle:dead];
            continue;
        }

        // blink
        float elapsed = (time - particle->birth);
#if 0
        static const float blinkSpeed = 10.0f;
        static const float blinkAmount = 0.2f;
        particle->alpha = 0.8f + ((0.5f + (cosf(M_PI * elapsed * blinkSpeed) / 2.0f)) * blinkAmount);
#endif
        particle->alpha = 0.8f;
        
        // fade
        static const float fadeTime = 3.0f;
        float fadeFraction = MIN(1.0f, elapsed / fadeTime);
        particle->alpha *= 1.0 - fadeFraction;
        if (fadeFraction >= 1.0f) {
            Particle *dead = particle;
            particle = particle->next;
            [self _freeParticle:dead];
            continue;
        }

        // scale
        if (fadeFraction < 0.08f)
            particle->size = fadeFraction / 0.08f;
        else if (fadeFraction > 0.8f)
            particle->size = 1.0 - ((fadeFraction - 0.8f) / 0.2f);
        else
            particle->size = 1.0f;
            
        // rotate
        float rotationRate = 5.0f;
        if (particleCount % 2 == 0)
            rotationRate = -rotationRate;
        particle->rotation += rotationRate * step;
        
        // color
        static const float hueSpeed = 90.0f;
        particle->hue += hueSpeed * step;
        
        particleCount++;
        particle = particle->next;
    }

    // global color cycle
    float hueCycleSpeed = 180.0f;
    _hueCycle = fmodf(_hueCycle + (hueCycleSpeed * step), 360.0f);
    
    // kill if last particle is gone
    if (_decay && !_firstParticle)
        return NO;
    
    return YES;
}

static void _checkGLError(void)
{
    GLenum error = glGetError();
    if (error) {
        fprintf(stderr, "GL Error: %x\n", error);
        exit(0);
    }
}

+ (void)begin
{
    glBlendFunc(GL_SRC_ALPHA, GL_ONE);
    glColor4f(1.0f, 1.0f, 1.0f, 1.0f);

    if (!_particleTexture)
        _particleTexture = [[GLTexture alloc] initWithName:@"particles.png"];
    [_particleTexture bind];
}

static void _addVertex(float x, float y, float uvx, float uvy, unsigned color);

- (void)draw
{
    // draw particles
    Particle *particle = _firstParticle;
    while (particle) {
    
        // half width and height
        float w = 42.0f * particle->size;

        // Instead of changing GL state (translate, rotate) we rotate the sprite's corners here.  This lets us batch sprites at any rotation.
        // Fixme not very efficient way to rotate :P
        float radians = particle->rotation + (M_PI / 4.0f);
        float topRightX = particle->x + (cos(radians) * w);
        float topRightY = particle->y + (sin(radians) * w);
        radians = particle->rotation + (M_PI * 3.0f / 4.0f);
        float topLeftX = particle->x + (cos(radians) * w);
        float topLeftY = particle->y + (sin(radians) * w);
        radians = particle->rotation + (M_PI * 5.0f / 4.0f);
        float bottomLeftX = particle->x + (cos(radians) * w);
        float bottomLeftY = particle->y + (sin(radians) * w);
        radians = particle->rotation + (M_PI * 7.0f / 4.0f);
        float bottomRightX = particle->x + (cos(radians) * w);
        float bottomRightY = particle->y + (sin(radians) * w);
        
        // Texture atlas
        float minUV[2];
        float maxUV[2];
        switch (particle->texture) {
            case 0:
                minUV[0] = 0.0f;
                minUV[1] = 0.0f;
                maxUV[0] = 0.5f;
                maxUV[1] = 0.5f;
            break;
            
            case 1:
            default:
                minUV[0] = 0.5f;
                minUV[1] = 0.0f;
                maxUV[0] = 1.0f;
                maxUV[1] = 0.5f;
            break;
        }
        
        unsigned char RGB[3];
        float HSV[3] = { particle->hue, 1.0f, 1.0f };
        _HSVToRGB(HSV, RGB);
        unsigned char shortAlpha = particle->alpha * 255.0f;
        
        unsigned color = (shortAlpha << 24) | (RGB[0] << 16) | (RGB[1] << 8) | (RGB[2] << 0);
        
        // Triangle #1
        _addVertex(topLeftX, topLeftY, minUV[0], minUV[1], color);
        _addVertex(topRightX, topRightY, maxUV[0], minUV[1], color);
        _addVertex(bottomLeftX, bottomLeftY, minUV[0], maxUV[1], color);
        
        // Triangle #2
        _addVertex(topRightX, topRightY, maxUV[0], minUV[1], color);
        _addVertex(bottomLeftX, bottomLeftY, minUV[0], maxUV[1], color);
        _addVertex(bottomRightX, bottomRightY, maxUV[0], maxUV[1], color);
        
        _vertexCount += 6;
        
        // Don't go over vert limit!
        if (_vertexCount >= MAX_VERTS) {
            _vertexCount = MAX_VERTS;
            break;
        }
        
        particle = particle->next;
    }
}

static void _addVertex(float x, float y, float uvx, float uvy, unsigned color)
{
    ParticleVert *vert = &_interleavedVerts[_vertexCount];
    vert->v[0] = x;
    vert->v[1] = y;
    vert->uv[0] = uvx;
    vert->uv[1] = uvy;
    vert->color = color;
    _vertexCount++;
}

+ (void)flush
{
    if (!_vertexCount)
        return;
        
    glVertexPointer(2, GL_SHORT, sizeof(ParticleVert), &_interleavedVerts[0].v);
    glTexCoordPointer(2, GL_FLOAT, sizeof(ParticleVert), &_interleavedVerts[0].uv);
    glColorPointer(4, GL_UNSIGNED_BYTE, sizeof(ParticleVert), &_interleavedVerts[0].color);
    glDrawArrays(GL_TRIANGLES, 0, _vertexCount);
    _vertexCount = 0;
}

- (void)reset
{
    // reset animation
    _lastTime = 0.0;
    _birth = 0.0;
    _lastEmitTime = 0.0;
    _decay = NO;
    
    // free particles
    Particle *particle = _firstParticle;
    while (particle) {
        Particle *next = particle->next;
        _particleFree(particle);
        particle = next;
    }
    
    _firstParticle = NULL;
    _lastParticle = NULL;
}

- (void)setLocation:(CGPoint)location fill:(BOOL)fill
{
    double time = [NSDate timeIntervalSinceReferenceDate];
    // if moved then fill the gap
    if (fill && !CGPointEqualToPoint(_location, location)) {
        float dx = _location.x - location.x;
        float dy = _location.y - location.y;
        static const float step = 5.0f;
        float distance = sqrt((dx * dx) + (dy * dy));
        unsigned count = distance / step;
        for (unsigned i = 0; i < count; i++) {
            float fraction = (float)i / (float)count;
            [self _emitParticleAtTime:time x:(_location.x + (dx * fraction)) y:(_location.y + (dy * fraction)) push:NO];
        }
    }
    
    _location = location;
}

- (void)setDecay:(BOOL)decay
{
    if (decay == _decay)
        return;
        
    _decay = decay;
}

@end
