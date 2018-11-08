//
//  GOLShaders.metal
//  MetalGameOfLife
//
//  Created by MikiTakahashi on 2018/11/09.
//  Copyright © 2018 MikiTakahashi. All rights reserved.
//

#include <metal_stdlib>

using namespace metal;

constant float2 kNeighborDirections[] = {
    float2(-1,-1), float2(-1,0), float2(-1,1),
    float2(0,-1), /* center */ float2(0,1),
    float2(1,-1), float2(1,0), float2(1,1)
};

constant float kSpawnProbability = 0.444;

constant int kCellValueAlive = 0;
constant int kCellValueDead = 255;

typedef struct {
    packed_float2 position;
    packed_float2 texCoords;
} VertexIn;

typedef struct {
    float4 position [[position]];
    float2 texCoords;
} FragmentVertex;

vertex FragmentVertex lighting_vertex(device VertexIn *vertexArray[[buffer(0)]],
                                      uint vertexIndex [[vertex_id]])
{
    FragmentVertex out;
    out.position = float4(vertexArray[vertexIndex].position,0,1);
    out.texCoords = vertexArray[vertexIndex].texCoords;
    return out;
}

fragment half4 lighting_fragment(FragmentVertex in [[stage_in]],
                                 texture2d<uint, access::sample> gameGrid [[texture(0)]],
                                 texture2d<uint, access::sample> colorMap [[texture(1)]])
{
    constexpr sampler nearestSampler(coord:: normalized, filter:: nearest);
    float deadTime = gameGrid.sample(nearestSampler, in.texCoords).r / 255.0;
    
    uint4 color = colorMap.sample(nearestSampler, float2(deadTime, 0));
    return half4(color);
}

static float hash(int2 v) {
    return fract(sin(dot(float2(v), float2(12.9898,78.233)))*43758.5453);
}

kernel void activate_random_neighbors(texture2d<uint, access::write> writeTexture [[texture(0)]],
                                      constant uint2 *cellPositions [[buffer(0)]],
                                      ushort2 gridPosition [[thread_position_in_grid]])
{
    for( ushort i =0; i<8; ++i) {
        int2 neighborPosition = int2(cellPositions[gridPosition.x]) + int2(kNeighborDirections[i]);
        ushort cellValue = (hash(neighborPosition) < kSpawnProbability) ? kCellValueAlive : kCellValueDead;
        writeTexture.write(cellValue, uint2(neighborPosition));
    }
}

kernel void game_of_life(texture2d<uint, access::sample> readTexture [[texture(0)]],
                         texture2d<uint, access::write> writeTexture [[texture(1)]],
                         sampler wrapSampler [[sampler(0)]],
                         ushort2 gridPosition [[thread_position_in_grid]]) {
    ushort width = readTexture.get_width();
    ushort height = readTexture.get_height();
    float2 bounds(width, height);
    float2 position = float2(gridPosition);
    
    if(gridPosition.x<width && gridPosition.y<height) {
        ushort neighbors = 0;
        for(int i=0; i<8; i++) {
            float2 coords = (position + kNeighborDirections[i] + float2(0.5)) / bounds;
            ushort cellValue = readTexture.sample(wrapSampler, coords).r;
            neighbors += (cellValue == kCellValueAlive) ? 1:0;
        }
    
        ushort deadFrames = readTexture.read(uint2(position)).r;
        bool alive = (deadFrames == 0 && (neighbors == 2 || neighbors == 3)) || (deadFrames > 0 && (neighbors == 3));
        
        ushort cellValue = alive ? kCellValueAlive : deadFrames + 1;

        writeTexture.write(cellValue, uint2(position));
    }
}
