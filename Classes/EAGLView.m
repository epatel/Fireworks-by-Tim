//
//  EAGLView.m
//  particleDemo
//
//  Created by Tim Omernick on 5/20/09.
//  Copyright ngmoco:) 2009. All rights reserved.
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


#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGLDrawable.h>
#import <AudioToolbox/AudioServices.h>

#import "EAGLView.h"
#import "ParticleSystem.h"
#import "GLTexture.h"

#define USE_DEPTH_BUFFER 0

static SystemSoundID _boomSoundIDs[3];

// A class extension to declare private methods
@interface EAGLView ()

@property (nonatomic, retain) EAGLContext *context;
@property (nonatomic, assign) NSTimer *animationTimer;

- (BOOL) createFramebuffer;
- (void) destroyFramebuffer;

@end


@implementation EAGLView

@synthesize context;
@synthesize animationTimer;
@synthesize animationInterval;


// You must implement this method
+ (Class)layerClass {
    return [CAEAGLLayer class];
}


//The GL view is stored in the nib file. When it's unarchived it's sent -initWithCoder:
- (id)initWithCoder:(NSCoder*)coder {
    
    if ((self = [super initWithCoder:coder])) {
        // Get the layer
        CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
        
        eaglLayer.opaque = YES;
        eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSNumber numberWithBool:NO], kEAGLDrawablePropertyRetainedBacking, kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];
        
        context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
        
        if (!context || ![EAGLContext setCurrentContext:context]) {
            [self release];
            return nil;
        }

        _particleSystems = [[NSMutableDictionary alloc] init];
        _oldSystems = [[NSMutableArray alloc] init];

        NSURL *soundURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"firework_6" ofType:@"wav"]];
        AudioServicesCreateSystemSoundID((CFURLRef)soundURL, &_boomSoundIDs[0]);
        soundURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"firework_2" ofType:@"wav"]];
        AudioServicesCreateSystemSoundID((CFURLRef)soundURL, &_boomSoundIDs[1]);
        soundURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"firework_3" ofType:@"wav"]];
        AudioServicesCreateSystemSoundID((CFURLRef)soundURL, &_boomSoundIDs[2]);
        
        animationInterval = 1.0 / 60.0;
    }
    return self;
}


- (void)drawView {
    
    [EAGLContext setCurrentContext:context];
    
    glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
    glViewport(0, 0, backingWidth, backingHeight);
    
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrthof(0, backingWidth, backingHeight, 0, 0, 1);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    
#if 0
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
#endif
    
    glEnable(GL_TEXTURE_2D);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
#if TARGET_IPHONE_SIMULATOR
    glColor4f(0, 0, 0, 0.2f);
#else
    glColor4f(0, 0, 0, 0.2f);
#endif
    
    glEnableClientState(GL_VERTEX_ARRAY);
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisableClientState(GL_COLOR_ARRAY);

    CGRect bounds = self.bounds;
    float vertices[] = {
        bounds.origin.x, bounds.origin.y,
        bounds.origin.x + bounds.size.width, bounds.origin.y,
        bounds.origin.x, bounds.origin.y + bounds.size.height,
        bounds.origin.x + bounds.size.width, bounds.origin.y + bounds.size.height
    };
    
    glVertexPointer(2, GL_FLOAT, 0, vertices);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glEnableClientState(GL_COLOR_ARRAY);

    [ParticleSystem begin];

    double now = [NSDate timeIntervalSinceReferenceDate];
    NSMutableArray *deadSystems = nil;
    for (NSValue *pointerValue in _particleSystems) {
        ParticleSystem *system = [_particleSystems objectForKey:pointerValue];
        if ([system animate:now])
            [system draw];
        else {
            if (!deadSystems)
                deadSystems = [NSMutableArray array];
            [deadSystems addObject:pointerValue];
        }
    }
    
    for (NSValue *pointerValue in deadSystems) {
        [_particleSystems removeObjectForKey:pointerValue];
    }
    
    NSMutableArray *deadOldSystems = nil;
    for (ParticleSystem *system in _oldSystems) {
        if ([system animate:now])
            [system draw];
        else {
            if (!deadOldSystems)
                deadOldSystems = [NSMutableArray array];
            [deadOldSystems addObject:system];
        }
    }

    [ParticleSystem flush];
    
    for (ParticleSystem *system in deadOldSystems) {
        [_oldSystems removeObjectIdenticalTo:system];
    }
    
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
    [context presentRenderbuffer:GL_RENDERBUFFER_OES];
}


- (void)layoutSubviews {
    [EAGLContext setCurrentContext:context];
    [self destroyFramebuffer];
    [self createFramebuffer];
    [self drawView];
}


- (BOOL)createFramebuffer {
    
    glGenFramebuffersOES(1, &viewFramebuffer);
    glGenRenderbuffersOES(1, &viewRenderbuffer);
    
    glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
    [context renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:(CAEAGLLayer*)self.layer];
    glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, viewRenderbuffer);
    
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &backingWidth);
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &backingHeight);
    
    if (USE_DEPTH_BUFFER) {
        glGenRenderbuffersOES(1, &depthRenderbuffer);
        glBindRenderbufferOES(GL_RENDERBUFFER_OES, depthRenderbuffer);
        glRenderbufferStorageOES(GL_RENDERBUFFER_OES, GL_DEPTH_COMPONENT16_OES, backingWidth, backingHeight);
        glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_DEPTH_ATTACHMENT_OES, GL_RENDERBUFFER_OES, depthRenderbuffer);
    }
    
    if(glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES) != GL_FRAMEBUFFER_COMPLETE_OES) {
        NSLog(@"failed to make complete framebuffer object %x", glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES));
        return NO;
    }
    
    return YES;
}


- (void)destroyFramebuffer {
    
    glDeleteFramebuffersOES(1, &viewFramebuffer);
    viewFramebuffer = 0;
    glDeleteRenderbuffersOES(1, &viewRenderbuffer);
    viewRenderbuffer = 0;
    
    if(depthRenderbuffer) {
        glDeleteRenderbuffersOES(1, &depthRenderbuffer);
        depthRenderbuffer = 0;
    }
}


- (void)startAnimation {
    self.animationTimer = [NSTimer scheduledTimerWithTimeInterval:animationInterval target:self selector:@selector(drawView) userInfo:nil repeats:YES];
}


- (void)stopAnimation {
    self.animationTimer = nil;
}


- (void)setAnimationTimer:(NSTimer *)newTimer {
    [animationTimer invalidate];
    animationTimer = newTimer;
}


- (void)setAnimationInterval:(NSTimeInterval)interval {
    
    animationInterval = interval;
    if (animationTimer) {
        [self stopAnimation];
        [self startAnimation];
    }
}


- (void)dealloc {
    
    [self stopAnimation];
    
    if ([EAGLContext currentContext] == context) {
        [EAGLContext setCurrentContext:nil];
    }
    
    [context release];  
    [super dealloc];
}

- (void)_playBoom
{
    int index = (random() % 3);
    AudioServicesPlaySystemSound(_boomSoundIDs[index]);
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    for (UITouch *touch in touches) {
        [self _playBoom];
        
        CGPoint location = [touch locationInView:self];
        
        ParticleSystem *system = [[ParticleSystem alloc] init];
        [system setLocation:location fill:NO];
        
        NSValue *key = [NSValue valueWithPointer:touch];
        ParticleSystem *existingSystem = [_particleSystems objectForKey:key];
        if (existingSystem)
            [_oldSystems addObject:existingSystem];
        [_particleSystems setObject:system forKey:key];
        [system release];
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    for (UITouch *touch in touches) {
        ParticleSystem *system = [_particleSystems objectForKey:[NSValue valueWithPointer:touch]];
        if (!system)
            continue;
            
        CGPoint location = [touch locationInView:self];
        [system setLocation:location fill:YES];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    for (UITouch *touch in touches) {
        ParticleSystem *system = [_particleSystems objectForKey:[NSValue valueWithPointer:touch]];
        if (!system)
            continue;
        
        [system setDecay:YES];
    }
}

@end
