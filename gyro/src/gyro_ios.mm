#include "gyro_private.h"
#include <extension/extension.h>
#include <script/script.h>
#include <dlib/vmath.h>

#import <dlib/log.h>

#if defined(DM_PLATFORM_IOS)

#import <CoreMotion/CoreMotion.h>



struct Gyro {
  CMMotionManager* motionManager;
  GyroListener listener;
} g_Gyro;

static void ObjCToLua(lua_State*L, id obj)
{
    if ([obj isKindOfClass:[NSString class]]) {
        const char* str = [((NSString*) obj) UTF8String];
        lua_pushstring(L, str);
    } else if ([obj isKindOfClass:[NSNumber class]]) {
        lua_pushnumber(L, [((NSNumber*) obj) doubleValue]);
    } else if ([obj isKindOfClass:[NSNull class]]) {
        lua_pushnil(L);
    } else if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary* dict = (NSDictionary*) obj;
        lua_createtable(L, 0, [dict count]);
        for (NSString* key in dict) {
            lua_pushstring(L, [key UTF8String]);
            id value = [dict objectForKey:key];
            ObjCToLua(L, (NSDictionary*) value);
            lua_rawset(L, -3);
        }
    } else if ([obj isKindOfClass:[NSArray class]]) {
        NSArray* a = (NSArray*) obj;
        lua_createtable(L, [a count], 0);
        for (int i = 0; i < [a count]; ++i) {
            ObjCToLua(L, [a objectAtIndex: i]);
            lua_rawseti(L, -2, i+1);
        }
    } else {
        dmLogWarning("Unsupported payload value '%s' (%s)", [[obj description] UTF8String], [[[obj class] description] UTF8String]);
        lua_pushnil(L);
    }
}

int Gyro_PlatformStart(lua_State* L) {
    Gyro* gyro = &g_Gyro;
    
    luaL_checktype(L, 1, LUA_TFUNCTION);
    lua_pushvalue(L, 1);
    int cb = dmScript::Ref(L, LUA_REGISTRYINDEX);

    if (gyro->listener.m_Callback != LUA_NOREF) {
      dmScript::Unref(gyro->listener.m_L, LUA_REGISTRYINDEX, gyro->listener.m_Callback);
      dmScript::Unref(gyro->listener.m_L, LUA_REGISTRYINDEX, gyro->listener.m_Self);
    }

    gyro->listener.m_L = dmScript::GetMainThread(L);
    gyro->listener.m_Callback = cb;
    dmScript::GetInstance(L);
    gyro->listener.m_Self = dmScript::Ref(L, LUA_REGISTRYINDEX);
    
    
    gyro->motionManager = [[CMMotionManager alloc] init];
    gyro->motionManager.gyroUpdateInterval = 1.0/60.0;
    
    //[gyro->motionManager startDeviceMotionUpdatesToQueue: [NSOperationQueue currentQueue]
    [gyro->motionManager startDeviceMotionUpdatesUsingReferenceFrame: CMAttitudeReferenceFrameXArbitraryCorrectedZVertical
                                                toQueue: [NSOperationQueue currentQueue]
                                            withHandler: ^(CMDeviceMotion *data, NSError *error)
                                            {
                                                CMAttitude* attitude = data.attitude;
                                                
                                                NSLog(@"attitude = [pitch %f, roll %f, yaw %f]", attitude.pitch, attitude.roll, attitude.yaw);
                                                
                                                lua_State* L = gyro->listener.m_L;
                                                int top = lua_gettop(L);
        
                                                lua_rawgeti(L, LUA_REGISTRYINDEX, gyro->listener.m_Callback);

                                                // Setup self
                                                lua_rawgeti(L, LUA_REGISTRYINDEX, gyro->listener.m_Self);
                                                lua_pushvalue(L, -1);
                                                dmScript::SetInstance(L);
                                                
                                                lua_pushnumber(L, attitude.pitch);
                                                lua_pushnumber(L, attitude.roll);
                                                lua_pushnumber(L, attitude.yaw);

                                                CMQuaternion quat = attitude.quaternion;
                                                Vectormath::Aos::Quat rot(quat.x, quat.y, quat.z, quat.w);
                                                dmScript::PushQuat(L, rot);
                                                
                                                CMRotationMatrix m4 = attitude.rotationMatrix;
                                                Vectormath::Aos::Matrix4 matrix4;
                                                matrix4.setElem(1, 1, m4.m11);
                                                matrix4.setElem(1, 2, m4.m12);
                                                matrix4.setElem(1, 3, m4.m13);
                                                matrix4.setElem(2, 1, m4.m21);
                                                matrix4.setElem(2, 2, m4.m22);
                                                matrix4.setElem(2, 3, m4.m23);
                                                matrix4.setElem(3, 1, m4.m31);
                                                matrix4.setElem(3, 2, m4.m32);
                                                matrix4.setElem(3, 3, m4.m33);
                                                dmScript::PushMatrix4(L, matrix4);
                                                
                                                int ret = lua_pcall(L, 6, LUA_MULTRET, 0);
                                                if (ret != 0) {
                                                    dmLogError("Error running gyro callback: %s", lua_tostring(L, -1));
                                                    lua_pop(L, 1);
                                                }
                                                assert(top == lua_gettop(L));
                                            }];
    // [gyro->motionManager startGyroUpdatesToQueue:[NSOperationQueue currentQueue]
    //                            withHandler: ^(CMGyroData *gyroData, NSError *error)
    //                                       {
    //                                         CMRotationRate rotate = gyroData.rotationRate;
    //                                         NSLog(@"rotation rate = [%f, %f, %f]", rotate.x, rotate.y, rotate.z);
    //                                         
    //                                         lua_State* L = gyro->listener.m_L;
    //                                         int top = lua_gettop(L);
    // 
    //                                         lua_rawgeti(L, LUA_REGISTRYINDEX, gyro->listener.m_Callback);
    // 
    //                                         // Setup self
    //                                         lua_rawgeti(L, LUA_REGISTRYINDEX, gyro->listener.m_Self);
    //                                         lua_pushvalue(L, -1);
    //                                         dmScript::SetInstance(L);
    //                                         
    //                                         lua_pushnumber(L, rotate.x);
    //                                         lua_pushnumber(L, rotate.y);
    //                                         lua_pushnumber(L, rotate.z);
    // 
    //                                         int ret = lua_pcall(L, 3, LUA_MULTRET, 0);
    //                                         if (ret != 0) {
    //                                             dmLogError("Error running gyro callback: %s", lua_tostring(L, -1));
    //                                             lua_pop(L, 1);
    //                                         }
    //                                         assert(top == lua_gettop(L));
    //                                         
    //                                       }];
    dmLogInfo("GYRO HAS STARTED");
    return 1;
}

int Gyro_PlatformStop(lua_State* L) {
  Gyro* gyro = &g_Gyro;
  if (gyro->motionManager != nil) {
    [gyro->motionManager stopGyroUpdates];
    [gyro->motionManager release];
    gyro->motionManager = nil;
    dmLogInfo("GYRO HAS STOPPED");
  }
  return 1;
}

#else

int Gyro_PlatformStart(lua_State* L) {
  return 1;
}

int Gyro_PlatformStop(lua_State* L) {
  return 1;
}

#endif // DM_PLATFORM_IOS
