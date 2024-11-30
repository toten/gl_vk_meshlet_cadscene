/*
 * Copyright (c) 2016-2022, NVIDIA CORPORATION.  All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * SPDX-FileCopyrightText: Copyright (c) 2016-2022 NVIDIA CORPORATION
 * SPDX-License-Identifier: Apache-2.0
 */


#version 450

#ifdef VULKAN 
  #extension GL_GOOGLE_include_directive : enable
  #extension GL_EXT_control_flow_attributes: require
  #define UNROLL_LOOP [[unroll]]
#else
  #extension GL_ARB_shading_language_include : enable
  #pragma optionNV(unroll all)  
  #define UNROLL_LOOP
#endif

  #extension GL_EXT_shader_explicit_arithmetic_types_int8  : require
  #extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

#include "common.h"

//////////////////////////////////////////////////
// UNIFORMS

#if IS_VULKAN


  layout(push_constant) uniform pushConstant{
    // x: mesh, y: prim, z: indexOffset, w: vertex
    uvec4     geometryOffsets;
    // x: meshFirst, y: meshMax
    uvec4     drawRange;
  };

  layout(std140,binding= SCENE_UBO_VIEW,set=DSET_SCENE) uniform sceneBuffer {
    SceneData scene;
  };

  layout(std140,binding=0,set=DSET_OBJECT) uniform objectBuffer {
    ObjectData object;
  };

  layout(std430, binding = GEOMETRY_SSBO_MESHLETDESC, set = DSET_GEOMETRY) buffer meshletDescBuffer {
    uvec4 meshletDescs[];
  };
  layout(std430, binding = 1, set = DSET_GEOMETRY) buffer meshletIndexOffsetBuffer {
    uint meshletIndexOffset[];
  };

   layout(std430, binding = GEOMETRY_SSBO_PRIM, set = DSET_GEOMETRY) buffer primIndexBuffer1 {
    uint    primIndices1[];
  };

  layout(std430, binding = GEOMETRY_SSBO_PRIM, set = DSET_GEOMETRY) buffer primIndexBuffer2 {
    uint8_t primIndices_u8[];
  };

  layout(binding=GEOMETRY_TEX_VBO,  set=DSET_GEOMETRY)  uniform samplerBuffer  texVbo;
  layout(binding=GEOMETRY_TEX_ABO,  set=DSET_GEOMETRY)  uniform samplerBuffer  texAbo;

  struct IndirectCommand
{
  uint      vertexCount;
  uint      instanceCount;
  uint      firstVertex;
  uint      firstInstance;
};

layout(std430, binding = 0, set = 3) buffer indirectCommandBuffer {
  IndirectCommand indirectCommand[];
};

  
#else

  layout(std140,binding=UBO_SCENE_VIEW) uniform sceneBuffer {
    SceneData scene;
  };

  layout(std140,binding=UBO_OBJECT) uniform objectBuffer {
    ObjectData object;
  };

#endif


/////////////////////////////////////////////////

#include "nvmeshlet_utils.glsl"

/////////////////////////////////////////////////

//////////////////////////////////////////////////
// INPUT

// We are using simple vertex attributes here, so
// that we can switch easily between fp32 and fp16 to
// investigate impact of vertex bandwith.
//
// In a more performance critical scenario we recommend the use
// of packed normals for CAD, like octant encoding and pack position
// and normal in a single 128-bit value.

#if 0
in layout(location=VERTEX_POS)      vec3 oPos;
in layout(location=VERTEX_NORMAL)   vec3 oNormal;
#if VERTEX_EXTRAS_COUNT
in layout(location=VERTEX_EXTRAS)   vec4 xtra[VERTEX_EXTRAS_COUNT];
#endif
#endif

// If you work from fixed vertex definitions and don't need dynamic
// format conversions by texture formats, or don't mind
// creating multiple shader permutations, you may want to
// use ssbos here, instead of tbos

vec3 getPosition( uint vidx ){
  return texelFetch(texVbo, int(vidx)).xyz;
}

vec3 getNormal( uint vidx ){
  return texelFetch(texAbo, int(vidx * VERTEX_NORMAL_STRIDE)).xyz;
}

vec4 getExtra( uint vidx, uint xtra ){
  return texelFetch(texAbo, int(vidx * VERTEX_NORMAL_STRIDE + 1 + xtra));
}

//////////////////////////////////////////////////
// OUTPUT

#if SHOW_PRIMIDS

  // nothing to output
  
#else

  layout(location=0) out Interpolants {
    vec3  wPos;    
    vec3  wNormal;
    flat uint meshletID;
  #if VERTEX_EXTRAS_COUNT
    vec4 xtra[VERTEX_EXTRAS_COUNT];
  #endif
} OUT;

#endif

#if IS_VULKAN && USE_CLIPPING
out float gl_ClipDistance[NUM_CLIPPING_PLANES];
#endif

vec4 procVertex(const uint vert, uint vidx)
{
  vec3 oPos = getPosition(vidx);
  vec3 wPos = (object.worldMatrix  * vec4(oPos,1)).xyz;
  vec4 hPos = (scene.viewProjMatrix * vec4(wPos,1));

  gl_Position = hPos;

#if !SHOW_PRIMIDS
  OUT.wPos = wPos;
  OUT.meshletID = 0;
#endif

  return hPos;
}


void procAttributes(const uint vert, uint vidx)
{
#if !SHOW_PRIMIDS && !USE_BARYCENTRIC_SHADING
  vec3 oNormal = getNormal(vidx);
  vec3 wNormal = mat3(object.worldMatrixIT) * oNormal;

  OUT.wNormal = wNormal;
  #if VERTEX_EXTRAS_COUNT
    UNROLL_LOOP
    for (int i = 0; i < VERTEX_EXTRAS_COUNT; i++) {
      vec4 xtra = getExtra(vidx, i);
      OUT.xtra[i] = xtra;
    }
  #endif
#endif
}

//////////////////////////////////////////////////
// VERTEX EXECUTION

void main()
{
  // from buffer which is a map from instance_id to meshlet_id
  uint id = gl_InstanceIndex + drawRange.z + drawRange.w;
  uint meshletID = indirectCommand[id].firstInstance;
  uvec4 desc = meshletDescs[meshletID + geometryOffsets.x];

  uint vertMax;
  uint primMax;

  uint vidxStart;
  uint vidxBits;
  uint vidxDiv;
  uint primStart;
  uint primDiv;

  decodeMeshlet(desc, vertMax, primMax, primStart, primDiv, vidxStart, vidxBits, vidxDiv);

  vidxStart += geometryOffsets.y / 4;
  primStart += geometryOffsets.y / 4;


  uint readBegin = primStart * 4;
  uint primRead = min(gl_VertexIndex/3, primMax);
  uint vert = primIndices_u8[readBegin + primRead*3 + gl_VertexIndex%3];
  uint vertLoad = min(vert, vertMax);

  {
    // the meshlet contains two set of indices
    // - vertex indices (which can be either 16 or 32 bit)
    //   are loaded here. The idx is manipulated
    //   as one 32 bit value contains either two 16 bits
    //   or just a single 32 bit.
    //   The bit shifting handles the 16 or 32 bit decoding
    //   
    // - primitive (triangle) indices are loaded
    //   later in bulk, see PRIMITIVE TOPOLOGY
  
    uint idx   = (vertLoad) >> (vidxDiv-1);
    uint shift = (vertLoad) &  (vidxDiv-1);

    uint vidx = primIndices1[idx + vidxStart];
    vidx <<= vidxBits * (1-shift);
    vidx >>= vidxBits;

    vidx += geometryOffsets.w;
    
    // here we do the work typically done in the vertex-shader
    procVertex(vert, vidx);
    procAttributes(vert, vidx);
  }
}
