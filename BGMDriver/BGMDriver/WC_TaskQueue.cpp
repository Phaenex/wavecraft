// This file is part of Background Music.
//
// Background Music is free software: you can redistribute it and/or
// modify it under the terms of the GNU General Public License as
// published by the Free Software Foundation, either version 2 of the
// License, or (at your option) any later version.
//
// Background Music is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Background Music. If not, see <http://www.gnu.org/licenses/>.

//
//  WC_TaskQueue.cpp
//  BGMDriver
//
//  Copyright © 2016, 2026 Kyle Neideck
//

// Self Include
#include "WC_TaskQueue.h"

// Local Includes
#include "BGM_Types.h"
#include "BGM_Utils.h"
#include "WC_PlugIn.h"
#include "WC_Clients.h"
#include "WC_ClientMap.h"
#include "WC_ClientTasks.h"

// PublicUtility Includes
#include "CAException.h"
#include "CADebugMacros.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wsign-conversion"
#include "CAAtomic.h"
#pragma clang diagnostic pop

// System Includes
#include <mach/mach_init.h>
#include <mach/mach_time.h>
#include <mach/task.h>


#pragma clang assume_nonnull begin

#pragma mark Construction/destruction

WC_TaskQueue::WC_TaskQueue()
:
    // The inline documentation for thread_time_constraint_policy.period says "A value of 0 indicates that there is no
    // inherent periodicity in the computation". So I figure setting the period to 0 means the scheduler will take as long
    // as it wants to wake our real-time thread, which is fine for us, but once it has only other real-time threads can
    // preempt us. (And that's only if they won't make our computation take longer than kRealTimeThreadMaximumComputationNs).
    mRealTimeThread(&WC_TaskQueue::RealTimeThreadProc,
                    this,
                    /* inPeriod = */ 0,
                    NanosToAbsoluteTime(kRealTimeThreadNominalComputationNs),
                    NanosToAbsoluteTime(kRealTimeThreadMaximumComputationNs),
                    /* inIsPreemptible = */ true),
    mNonRealTimeThread(&WC_TaskQueue::NonRealTimeThreadProc, this)
{
    // Init the semaphores
    auto createSemaphore = [] () {
        semaphore_t theSemaphore;
        kern_return_t theError = semaphore_create(mach_task_self(), &theSemaphore, SYNC_POLICY_FIFO, 0);
        
        BGM_Utils::ThrowIfMachError("WC_TaskQueue::WC_TaskQueue", "semaphore_create", theError);
        
        ThrowIf(theSemaphore == SEMAPHORE_NULL,
                CAException(kAudioHardwareUnspecifiedError),
                "WC_TaskQueue::WC_TaskQueue: Could not create semaphore");
        
        return theSemaphore;
    };
    
    mRealTimeThreadWorkQueuedSemaphore = createSemaphore();
    mNonRealTimeThreadWorkQueuedSemaphore = createSemaphore();
    mRealTimeThreadSyncTaskCompletedSemaphore = createSemaphore();
    mNonRealTimeThreadSyncTaskCompletedSemaphore = createSemaphore();
    
    // Pre-allocate enough tasks in mNonRealTimeThreadTasksFreeList that the real-time threads should never have to
    // allocate memory when adding a task to the non-realtime queue.
    for(UInt32 i = 0; i < kNonRealTimeThreadTaskBufferSize; i++)
    {
        WC_Task* theTask = new WC_Task;
        mNonRealTimeThreadTasksFreeList.push_NA(theTask);
    }
    
    // Start the worker threads
    mRealTimeThread.Start();
    mNonRealTimeThread.Start();
}

WC_TaskQueue::~WC_TaskQueue()
{
    // Join the worker threads
    BGMLogAndSwallowExceptionsMsg("WC_TaskQueue::~WC_TaskQueue", "QueueSync", ([&] {
        QueueSync(kBGMTaskStopWorkerThread, /* inRunOnRealtimeThread = */ true);
        QueueSync(kBGMTaskStopWorkerThread, /* inRunOnRealtimeThread = */ false);
    }));

    // Destroy the semaphores
    auto destroySemaphore = [] (semaphore_t inSemaphore) {
        kern_return_t theError = semaphore_destroy(mach_task_self(), inSemaphore);
        
        BGM_Utils::LogIfMachError("WC_TaskQueue::~WC_TaskQueue", "semaphore_destroy", theError);
    };
    
    destroySemaphore(mRealTimeThreadWorkQueuedSemaphore);
    destroySemaphore(mNonRealTimeThreadWorkQueuedSemaphore);
    destroySemaphore(mRealTimeThreadSyncTaskCompletedSemaphore);
    destroySemaphore(mNonRealTimeThreadSyncTaskCompletedSemaphore);
    
    WC_Task* theTask;
    
    // Delete the tasks in the non-realtime tasks free list
    while((theTask = mNonRealTimeThreadTasksFreeList.pop_atomic()) != NULL)
    {
        delete theTask;
    }
    
    // Delete any tasks left on the non-realtime queue that need to be
    while((theTask = mNonRealTimeThreadTasks.pop_atomic()) != NULL)
    {
        if(!theTask->IsSync())
        {
            delete theTask;
        }
    }
}

//static
UInt32  WC_TaskQueue::NanosToAbsoluteTime(UInt32 inNanos)
{
    // Converts a duration from nanoseconds to absolute time (i.e. number of bus cycles). Used for calculating
    // the real-time thread's time constraint policy.
    
    mach_timebase_info_data_t theTimebaseInfo;
    mach_timebase_info(&theTimebaseInfo);
    
    Float64 theTicksPerNs = static_cast<Float64>(theTimebaseInfo.denom) / theTimebaseInfo.numer;
    return static_cast<UInt32>(inNanos * theTicksPerNs);
}

#pragma mark Task queueing

void    WC_TaskQueue::QueueSync_SwapClientShadowMaps(WC_ClientMap* inClientMap)
{
    // TODO: Is there any reason to use uintptr_t when we pass pointers to tasks like this? I can't think of any
    //       reason for a system to have (non-function) pointers larger than 64-bit, so I figure they should fit.
    //
    //       From http://en.cppreference.com/w/cpp/language/reinterpret_cast:
    //       "A pointer converted to an integer of sufficient size and back to the same pointer type is guaranteed
    //        to have its original value [...]"
    QueueSync(kBGMTaskSwapClientShadowMaps, /* inRunOnRealtimeThread = */ true, reinterpret_cast<UInt64>(inClientMap));
}

void    WC_TaskQueue::QueueAsync_SendPropertyNotification(AudioObjectPropertySelector inProperty, AudioObjectID inDeviceID)
{
    DebugMsg("WC_TaskQueue::QueueAsync_SendPropertyNotification: Queueing property notification. inProperty=%u inDeviceID=%u",
             inProperty,
             inDeviceID);
    WC_Task theTask(kBGMTaskSendPropertyNotification, /* inIsSync = */ false, inProperty, inDeviceID);
    QueueOnNonRealtimeThread(theTask);
}

UInt64    WC_TaskQueue::QueueSync(BGM_TaskID inTaskID, bool inRunOnRealtimeThread, UInt64 inTaskArg1, UInt64 inTaskArg2)
{
    DebugMsg("WC_TaskQueue::QueueSync: Queueing task synchronously to be processed on the %s thread. inTaskID=%d inTaskArg1=%llu inTaskArg2=%llu",
             (inRunOnRealtimeThread ? "realtime" : "non-realtime"),
             inTaskID,
             inTaskArg1,
             inTaskArg2);
    
    // Create the task
    WC_Task theTask(inTaskID, /* inIsSync = */ true, inTaskArg1, inTaskArg2);
    
    // Add the task to the queue
    TAtomicStack<WC_Task>& theTasks = (inRunOnRealtimeThread ? mRealTimeThreadTasks : mNonRealTimeThreadTasks);
    theTasks.push_atomic(&theTask);
    
    // Wake the worker thread so it'll process the task. (Note that semaphore_signal has an implicit barrier.)
    kern_return_t theError = semaphore_signal(inRunOnRealtimeThread ? mRealTimeThreadWorkQueuedSemaphore : mNonRealTimeThreadWorkQueuedSemaphore);
    BGM_Utils::ThrowIfMachError("WC_TaskQueue::QueueSync", "semaphore_signal", theError);
    
    // Wait until the task has been processed.
    //
    // The worker thread signals all threads waiting on this semaphore when it finishes a task. The comments in WorkerThreadProc
    // explain why we have to check the condition in a loop here.
    bool didLogTimeoutMessage = false;
    while(!theTask.IsComplete())
    {
        semaphore_t theTaskCompletedSemaphore =
            inRunOnRealtimeThread ? mRealTimeThreadSyncTaskCompletedSemaphore : mNonRealTimeThreadSyncTaskCompletedSemaphore;
        // TODO: Because the worker threads use semaphore_signal_all instead of semaphore_signal, a thread can miss the signal if
        //       it isn't waiting at the right time. Using a timeout for now as a temporary fix so threads don't get stuck here.
        theError = semaphore_timedwait(theTaskCompletedSemaphore,
                                       (mach_timespec_t){ 0, kRealTimeThreadMaximumComputationNs * 4 });
        
        if(theError == KERN_OPERATION_TIMED_OUT)
        {
            if(!didLogTimeoutMessage && inRunOnRealtimeThread)
            {
                DebugMsg("WC_TaskQueue::QueueSync: Task %d taking longer than expected.", theTask.GetTaskID());
                didLogTimeoutMessage = true;
            }
        }
        else
        {
            BGM_Utils::ThrowIfMachError("WC_TaskQueue::QueueSync", "semaphore_timedwait", theError);
        }
        
        CAMemoryBarrier();
    }
    
    if(didLogTimeoutMessage)
    {
        DebugMsg("WC_TaskQueue::QueueSync: Late task %d finished.", theTask.GetTaskID());
    }
    
    if(theTask.GetReturnValue() != INT64_MAX)
    {
        DebugMsg("WC_TaskQueue::QueueSync: Task %d returned %llu.", theTask.GetTaskID(), theTask.GetReturnValue());
    }
    
    return theTask.GetReturnValue();
}

void   WC_TaskQueue::QueueOnNonRealtimeThread(WC_Task inTask)
{
    // Add the task to our task list
    WC_Task* freeTask = mNonRealTimeThreadTasksFreeList.pop_atomic();
    
    if(freeTask == NULL)
    {
        LogWarning("WC_TaskQueue::QueueOnNonRealtimeThread: No pre-allocated tasks left in the free list. Allocating new task.");
        freeTask = new WC_Task;
    }
    
    *freeTask = inTask;
    
    mNonRealTimeThreadTasks.push_atomic(freeTask);
    
    // Signal the worker thread to process the task. (Note that semaphore_signal has an implicit barrier.)
    kern_return_t theError = semaphore_signal(mNonRealTimeThreadWorkQueuedSemaphore);
    BGM_Utils::ThrowIfMachError("WC_TaskQueue::QueueOnNonRealtimeThread", "semaphore_signal", theError);
}

#pragma mark Worker threads

void    WC_TaskQueue::AssertCurrentThreadIsRTWorkerThread(const char* inCallerMethodName)
{
#if DEBUG  // This Assert macro always checks the condition, even in release builds if the compiler doesn't optimise it away
    if(!mRealTimeThread.IsCurrentThread())
    {
        DebugMsg("%s should only be called on the realtime worker thread.", inCallerMethodName);
        __ASSERT_STOP;  // TODO: Figure out a better way to assert with a formatted message
    }
    
    Assert(mRealTimeThread.IsTimeConstraintThread(), "mRealTimeThread should be in a time-constraint priority band.");
#else
    #pragma unused (inCallerMethodName)
#endif
}

//static
void* __nullable    WC_TaskQueue::RealTimeThreadProc(void* inRefCon)
{
    DebugMsg("WC_TaskQueue::RealTimeThreadProc: The realtime worker thread has started");
    
    WC_TaskQueue* refCon = static_cast<WC_TaskQueue*>(inRefCon);
    refCon->WorkerThreadProc(refCon->mRealTimeThreadWorkQueuedSemaphore,
                             refCon->mRealTimeThreadSyncTaskCompletedSemaphore,
                             &refCon->mRealTimeThreadTasks,
                             NULL,
                             [&] (WC_Task* inTask) { return refCon->ProcessRealTimeThreadTask(inTask); });
    
    return NULL;
}

//static
void* __nullable    WC_TaskQueue::NonRealTimeThreadProc(void* inRefCon)
{
    DebugMsg("WC_TaskQueue::NonRealTimeThreadProc: The non-realtime worker thread has started");
    
    WC_TaskQueue* refCon = static_cast<WC_TaskQueue*>(inRefCon);
    refCon->WorkerThreadProc(refCon->mNonRealTimeThreadWorkQueuedSemaphore,
                             refCon->mNonRealTimeThreadSyncTaskCompletedSemaphore,
                             &refCon->mNonRealTimeThreadTasks,
                             &refCon->mNonRealTimeThreadTasksFreeList,
                             [&] (WC_Task* inTask) { return refCon->ProcessNonRealTimeThreadTask(inTask); });
    
    return NULL;
}

void    WC_TaskQueue::WorkerThreadProc(semaphore_t inWorkQueuedSemaphore, semaphore_t inSyncTaskCompletedSemaphore, TAtomicStack<WC_Task>* inTasks, TAtomicStack2<WC_Task>* __nullable inFreeList, std::function<bool(WC_Task*)> inProcessTask)
{
    bool theThreadShouldStop = false;
    
    while(!theThreadShouldStop)
    {
        // Wait until a thread signals that it's added tasks to the queue.
        //
        // Note that we don't have to hold any lock before waiting. If the semaphore is signalled before we begin waiting we'll
        // still get the signal after we do.
        kern_return_t theError = semaphore_wait(inWorkQueuedSemaphore);
        BGM_Utils::ThrowIfMachError("WC_TaskQueue::WorkerThreadProc", "semaphore_wait", theError);
        
        // Fetch the tasks from the queue.
        //
        // The tasks need to be processed in the order they were added to the queue. Since pop_all_reversed is atomic, other threads
        // can't add new tasks while we're reading, which would mix up the order.
        WC_Task* theTask = inTasks->pop_all_reversed();
        
        while(theTask != NULL &&
              !theThreadShouldStop)  // Stop processing tasks if we're shutting down
        {
            WC_Task* theNextTask = theTask->mNext;
            
            BGMAssert(!theTask->IsComplete(),
                      "WC_TaskQueue::WorkerThreadProc: Cannot process already completed task (ID %d)",
                      theTask->GetTaskID());
            
            BGMAssert(theTask != theNextTask,
                      "WC_TaskQueue::WorkerThreadProc: WC_Task %p (ID %d) was added to %s multiple times. arg1=%llu arg2=%llu",
                      theTask,
                      theTask->GetTaskID(),
                      (inTasks == &mRealTimeThreadTasks ? "mRealTimeThreadTasks" : "mNonRealTimeThreadTasks"),
                      theTask->GetArg1(),
                      theTask->GetArg2());
            
            // Process the task
            theThreadShouldStop = inProcessTask(theTask);
            
            // If the task was queued synchronously, let the thread that queued it know we're finished
            if(theTask->IsSync())
            {
                // Marking the task as completed allows QueueSync to return, which means it's possible for theTask to point to
                // invalid memory after this point.
                CAMemoryBarrier();
                theTask->MarkCompleted();
                
                // Signal any threads waiting for their task to be processed.
                //
                // We use semaphore_signal_all instead of semaphore_signal to avoid a race condition in QueueSync. It's possible
                // for threads calling QueueSync to wait on the semaphore in an order different to the order of the tasks they just
                // added to the queue. So after each task is completed we have every waiting thread check if it was theirs.
                //
                // Note that semaphore_signal_all has an implicit barrier.
                theError = semaphore_signal_all(inSyncTaskCompletedSemaphore);
                BGM_Utils::ThrowIfMachError("WC_TaskQueue::WorkerThreadProc", "semaphore_signal_all", theError);
            }
            else if(inFreeList != NULL)
            {
                // After completing an async task, move it to the free list so the memory can be reused
                inFreeList->push_atomic(theTask);
            }
            
            theTask = theNextTask;
        }
    }
}

bool    WC_TaskQueue::ProcessRealTimeThreadTask(WC_Task* inTask)
{
    AssertCurrentThreadIsRTWorkerThread("WC_TaskQueue::ProcessRealTimeThreadTask");
    
    switch(inTask->GetTaskID())
    {
        case kBGMTaskStopWorkerThread:
            DebugMsg("WC_TaskQueue::ProcessRealTimeThreadTask: Stopping");
            // Return that the thread should stop itself
            return true;
            
        case kBGMTaskSwapClientShadowMaps:
            {
                DebugMsg("WC_TaskQueue::ProcessRealTimeThreadTask: Swapping the shadow maps in WC_ClientMap");
                WC_ClientMap* theClientMap = reinterpret_cast<WC_ClientMap*>(inTask->GetArg1());
                WC_ClientTasks::SwapInShadowMapsRT(theClientMap);
            }
            break;
            
        default:
            Assert(false, "WC_TaskQueue::ProcessRealTimeThreadTask: Unexpected task ID");
            break;
    }
    
    return false;
}

bool    WC_TaskQueue::ProcessNonRealTimeThreadTask(WC_Task* inTask)
{
#if DEBUG  // This Assert macro always checks the condition, if for some reason the compiler doesn't optimise it away, even in release builds
    Assert(mNonRealTimeThread.IsCurrentThread(), "ProcessNonRealTimeThreadTask should only be called on the non-realtime worker thread.");
    Assert(mNonRealTimeThread.IsTimeShareThread(), "mNonRealTimeThread should not be in a time-constraint priority band.");
#endif
    
    switch(inTask->GetTaskID())
    {
        case kBGMTaskStopWorkerThread:
            DebugMsg("WC_TaskQueue::ProcessNonRealTimeThreadTask: Stopping");
            // Return that the thread should stop itself
            return true;
            
        case kBGMTaskSendPropertyNotification:
            DebugMsg("WC_TaskQueue::ProcessNonRealTimeThreadTask: Processing kBGMTaskSendPropertyNotification");
            {
                AudioObjectPropertyAddress thePropertyAddress[] = {
                    { static_cast<UInt32>(inTask->GetArg1()), kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain } };
                WC_PlugIn::Host_PropertiesChanged(static_cast<AudioObjectID>(inTask->GetArg2()), 1, thePropertyAddress);
            }
            break;
            
        default:
            Assert(false, "WC_TaskQueue::ProcessNonRealTimeThreadTask: Unexpected task ID");
            break;
    }
    
    return false;
}

#pragma clang assume_nonnull end

