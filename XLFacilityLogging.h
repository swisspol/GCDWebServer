/*
 Copyright (c) 2012-2014, Pierre-Olivier Latour
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * The name of Pierre-Olivier Latour may not be used to endorse
 or promote products derived from this software without specific
 prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL PIERRE-OLIVIER LATOUR BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "XLFacilityMacros.h"

/**
 *  This header file allows to use XLFacility logging system with GCDWebServer:
 *  https://github.com/swisspol/XLFacility
 *
 *  To use, first add this header file to your Xcode project then add a new
 *  build setting "GCC_PREPROCESSOR_DEFINITIONS_NOT_USED_IN_PRECOMPS" with this
 *  value:
 *
 *  __GCDWEBSERVER_LOGGING_HEADER__=\"XLFacilityLogging.h\"
 *
 */

#define LOG_DEBUG(...) XLOG_DEBUG(__VA_ARGS__)
#define LOG_VERBOSE(...) XLOG_VERBOSE(__VA_ARGS__)
#define LOG_INFO(...) XLOG_INFO(__VA_ARGS__)
#define LOG_WARNING(...) XLOG_WARNING(__VA_ARGS__)
#define LOG_ERROR(...) XLOG_ERROR(__VA_ARGS__)
#define LOG_EXCEPTION(__EXCEPTION__) XLOG_EXCEPTION(__EXCEPTION__)

#define DCHECK(__CONDITION__) XLOG_DEBUG_CHECK(__CONDITION__)
#define DNOT_REACHED() XLOG_DEBUG_UNREACHABLE()
