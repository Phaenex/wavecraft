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
//  WC_ClientTasks.h
//  BGMDriver
//
//  Copyright © 2016 Kyle Neideck
//
//  The interface between the client classes (WC_Client, WC_Clients and WC_ClientMap) and WC_TaskQueue.
//

#ifndef __BGMDriver__BGM_ClientTasks__
#define __BGMDriver__BGM_ClientTasks__

// Local Includes
#include "WC_Clients.h"
#include "WC_ClientMap.h"


// Forward Declarations
class WC_TaskQueue;


#pragma clang assume_nonnull begin

class WC_ClientTasks
{
    
    friend class WC_TaskQueue;
    
private:
    static void                            SwapInShadowMapsRT(WC_ClientMap* inClientMap) { inClientMap->SwapInShadowMapsRT(); }
    
};

#pragma clang assume_nonnull end

#endif /* __BGMDriver__BGM_ClientTasks__ */

