# StoryPoint burndown script for powershell.
# Author: Tariq Ayad

# Description:
# This script will
#   1.  Iterate through each of your user story's in the current sprint
#   2.  Calculate the story points per task under each of the above user stories
#   3.  Assign the calculated story points to the remaining hours of each task.
#   4.  If the task is closed, update the remaining hours to 0


# Prerequisites
#   You need to VSTS Queries to be created
#   1. Query to show the pending tasks from the previous iteration = the remaining hours of these need to be updated to 0 when they are clsoed
#   2. Query to show All User Stories and Bugs in teh current iteration

# Id of query showing pending tasks in the previous iteration
$pendingTasksPrevIterationQueryId = ""

# Id of query showing user stories and bugs in the curent iteration
$currentIterationUSBUGSQueryId = ""

# url of the team project
$collectionUri = ""

Write-Host "Working on Current Iteration US & Bugs"

# Get the User Stories for the current iteration
$curIterationWorkItems = $collectionUri + $TeamProject + '/_apis/wit/wiql/'+ $currentIterationUSBUGSQueryId + '?api-version=2.2'

write-host 'calling:' $curIterationWorkItems

$curIterWorkItems  = Invoke-RestMethod -Method Get -ContentType application/json -Uri $curIterationWorkItems -UseDefaultCredentials 

foreach ($curIterWorkItemMeta in $curIterWorkItems.workItems)
{
    $usQuery =$curIterWorkItemMeta.url + "?`$expand=all"
    write-host Calling $usQuery

    $curIterWorkItem =  Invoke-RestMethod -Method Get -ContentType application/json -Uri $usQuery -UseDefaultCredentials 
    
    # Get the storypoints of the User Story
    $storyPoints = $curIterWorkItem.fields."Microsoft.VSTS.Scheduling.StoryPoints"

    write-host User Story $curIterWorkItem.fields."System.Id" has $storyPoints storypoints
    
    if ($storyPoints -ne $null)
    {
        # Count the number of tasks
        $relatedTasks = $curIterWorkItem.relations | Where-Object {$_.rel -eq "System.LinkTypes.Hierarchy-Forward"}        

        if ($relatedTasks )
        {            
            if ($relatedTasks -is [array])
            {
                $numberOfTasks = $relatedTasks.Count
            }
            else
            {
                $numberOfTasks = 1   
            }

            if ($numberOfTasks -gt 0)
            {
                Write-Host Number of Tasks $numberOfTasks
                $pointsPerTask = [math]::Round($storyPoints/$numberOfTasks,2)
                write-host Points per Task:  $pointsPerTask                

                foreach ($relatedTask in $relatedTasks)
                {
                    $taskUrl = $relatedTask.url
                    Write-host Retrieving Task $taskUrl

                    $curIterWorkTask =  Invoke-RestMethod -Method Get -ContentType application/json -Uri $taskUrl -UseDefaultCredentials 
                    
                    $state = $curIterWorkTask.fields."System.State"

                    write-host WorkItem : $curIterWorkTask.fields."System.Id" $state $curIterWorkTask.fields."System.AssignedTo" 

                    if ($state -eq "Closed")
                    {
                        $originalHours = $pointsPerTask
                        $remainingHours = 0
                        $completedHours = $pointsPerTask
                    }
                    else
                    {
                        $originalHours = $pointsPerTask
                        $remainingHours = $pointsPerTask
                        $completedHours = 0
                    }

                    $curIterPatchUrl = $curIterWorkTask.url +  '?api-version=2.2'

                    $updateBody = '[{"op":"add","path":"/fields/Microsoft.VSTS.Scheduling.RemainingWork","value":'+ $remainingHours +'}, {"op":"add","path":"/fields/Microsoft.VSTS.Scheduling.CompletedWork","value":' + $completedHours + '} , {"op":"add","path":"/fields/Microsoft.VSTS.Scheduling.OriginalEstimate","value":' + $originalHours + '}]'

                    write-host Patching + $curIterPatchUrl
                    $patchResponse  = Invoke-RestMethod -Method Patch -ContentType application/json-patch+json -Uri $curIterPatchUrl -UseDefaultCredentials -Body $updateBody

                    # write-host $patchResponse    
                    write-host
                }
            }
        }
        write-host
        write-host

    }   

    write-host ------
}



# Retrieve All the Pending Tasks from the previous Sprint
Write-Host "Working on Tasks from Previous Sprint"

$prevIterationTasks = $collectionUri + $TeamProject + '/_apis/wit/wiql/'+ $pendingTasksPrevIterationQueryId + '?api-version=2.2'

write-host 'calling:' $prevIterationTasks

$prevIterationWorkItems  = Invoke-RestMethod -Method Get -ContentType application/json -Uri $prevIterationTasks -UseDefaultCredentials 

# Filter for all the Task nodes
$prevIterationTasks = $prevIterationWorkItems.workItemRelations  | Where-Object {$_.rel -eq "System.LinkTypes.Hierarchy-Forward"}        

foreach ($prevIterTaskMeta in $prevIterationTasks)
{
    $prevIterTaskUrl = $prevIterTaskMeta.target.url
    write-host Retrieving Task $prevIterTaskMeta.target.id $prevIterTaskUrl

    $prevIterTask =  Invoke-RestMethod -Method Get -ContentType application/json -Uri $prevIterTaskUrl -UseDefaultCredentials 
    $prevIterTaskState =  $prevIterTask.fields."System.State"

    if ($prevIterTaskState -eq "Closed")
    {
        $originalHours = $prevIterTask.fieldsds."Microsoft.VSTS.Scheduling.OriginalEstimate"
        $remainingHours =  $prevIterTask.fields."Microsoft.VSTS.Scheduling.RemainingWork"
        $completedHours = $prevIterTask.fields."Microsoft.VSTS.Scheduling.CompletedWork"
        write-host "O" $originalHours
        Write-Host "R" $remainingHours
        Write-Host "C" $completedHours

        if ($remainingHours -gt 0)
        {
            $updateBodyPrev = '[{"op":"add","path":"/fields/Microsoft.VSTS.Scheduling.RemainingWork","value":0}, {"op":"add","path":"/fields/Microsoft.VSTS.Scheduling.CompletedWork","value":' + $remainingHours + '}]'
        
            $patchUrl =  $prevIterTaskUrl +  '?api-version=2.2'
            write-host Patching + $patchUrl
            $patchResponse  = Invoke-RestMethod -Method Patch -ContentType application/json-patch+json -Uri $patchUrl -UseDefaultCredentials -Body $updateBodyPrev

            #write-host $patchResponse    
        }
        else
        {
            Write-Host No Update
        }
    }
    
}
