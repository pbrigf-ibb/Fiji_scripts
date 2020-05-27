#########################################################
################# MAKING PLATE MONTAGES #################
#########################################################
# screen data are located in a special folder on the S drive

master <- 'S:/S12_copy/' # declare master directory
sink(file = paste0(master, '/plate montage log.txt'), append = T, split = T) # begin logging progress into file
cat(format(Sys.time()), '\t', 'begin \n')
start_time <- Sys.time()

library(magrittr)
library(tidyr)
library(dplyr)
library(lubridate)
library(acutils)
setwd(master)
cat(format(Sys.time()), '\t', 'compile file lists \n') ######################## pacemaker
screenlog <- read.delim('screenlog_S14.txt') # load screen log
cat(format(Sys.time()), '\t', 'plate copies present: \n')
copies <- list.files() %>% grep('[0-9]{3}[A-Z,0-9]\\.[0-9]{8}\\.S[0-9]{2}\\.[A-Z][0-9]{2}', ., value = T ) %>% data.frame(plateno = .) # list present plate data
print(copies)
cat(format(Sys.time()), '\t', 'plates absent: \n')
missing <- anti_join(screenlog, copies) %>% # list plates that have not been copied
  separate(plateno, c('plate', 'prepared', 'screen', 'replica'), sep = '\\.', remove = F) %>%
  mutate(plate = gsub('[A-Z]', '', plate)) %>% select(plateno, plate, replica, plated)
print(missing)
ready <- left_join(copies, screenlog) %>% # prepare neat table of plates ready for processing
  separate(plateno, c('plate', 'prepared', 'screen', 'replica'), sep = '\\.', remove = F) %>% mutate(plate = gsub('[A-Z]', '', plate))
cat(format(Sys.time()), '\t', 'plates to delete: \n')
delete <- ready %>% # list plate folders to delete (the older of the duplicated ones)
    group_by(plate, replica) %>% filter(plated != max(plated)) %>% select(plateno, plate, replica, plated) %>% data.frame
print(delete)
cat(format(Sys.time()), '\t', 'deleting excess plates\n') ######################## pacemaker
unlink(delete$plateno, recursive = T, force = T) # delete the folders
post_delete <- ready %>% # repeat listing of the folders to be deleted
  group_by(plate, replica) %>% filter(plated != max(plated)) %>% select(plateno, plate, replica, plated) %>% data.frame
cat(format(Sys.time()), '\t', 'checking deletion \n') ######################## pacemaker
if (nrow(post_delete) != 0) { # verify that the list is empty, i.e. the folders have been deleted; if not, terminate
  cat(format(Sys.time()), '\t', 'some plates have not been removed \n terminating script')
  stop()
}

cat(format(Sys.time()), '\t', 'preparing plate lists for processing \n') ######################## pacemaker
copies_left <- list.files() %>% grep('[0-9]{3}[A-Z,0-9]\\.[0-9]{8}\\.S[0-9]{2}\\.[A-Z][0-9]{2}', ., value = T ) %>% data.frame(plateno = .) # list present plate data
ready_left <- left_join(copies_left, screenlog) %>% # prepare new neat table of data left
  separate(plateno, c('plate', 'prepared', 'screen', 'replica'), sep = '\\.', remove = F) %>% mutate(plate = gsub('[A-Z]', '', plate))

cat(format(Sys.time()), '\t', 'checking for / loading processing log \n') ######################## pacemaker
if (file.exists('processing_log.rda')) load('processing_log.rda') else processing_log <- vector('character')

plates <- ready_left$plateno %>% as.character

###############################################
### prepare image files for making montages ###
###############################################
cat(format(Sys.time()), '\t', 'moving on \n') ######################## pacemaker
# the numbers of the present field of view positions do not correspond to the final positions of the tile in a 3x2 montage
# therefore, the files must be renumbered
# prepare the tables for renumbering
a6 <- 1:6 %>% matrix(3,2)
b6 <- 1:6 %>% matrix(3,2,T)
replacement_table <- data.frame(before = as.vector(a6), after = as.vector(b6)) %>% arrange(before)


change_file_names <- function(x, ...) {
# function that will produce new file names
  replace_number <- function(x, rp, ...) {
  # function that switches integers according to a key supplied as a data frame
  # rp is the key
  # if none is supplied, the function will scope for an object called "replacement_table"
    if (missing(rp)) rp <- replacement_table
    return(rp[rp$before == x, 'after'])
  }
  # split file names and wrap them all into a matrix
  x_in_parts <- strsplit(x, '--') %>% do.call(rbind, .)
  # in column 1 (plate position):
  # add zeros
  x_in_parts[,1] <- insert_zeros(x_in_parts[,1])
  # in column 3 (position):
  # strip the letter P, convert to numeric, switch, paste a P at beginning and add zeros
  x_in_parts[,3] <- x_in_parts[,3] %>% 
    gsub('^P', '', .) %>% as.numeric %>% 
    sapply(replace_number, ...) %>% 
    paste0('P', .) %>% insert_zeros(., 1)
  # in column 6:
  # strip the channel name bare
  x_in_parts[,6] <- x_in_parts[,6] %>% 
    gsub('(_zMax)|()\\.tif', '', .)
  # rearrange useful data (may skip this later on)
  parts <- x_in_parts[, c(1,3,6)]
  # construct new names
  new_names <- apply(parts, 1, paste, collapse = '--')
  return(new_names)
} # function that changes files names


cat(format(Sys.time()), '\t', 'plate processing begins \n') ######################## pacemaker
for (d in plates) {
  cat(format(Sys.time()), '\t', 'plate', d, '\n') ######################## pacemaker
  if (d %in% processing_log) {
    cat(format(Sys.time()), '\t', '\t plate already done, moving on \n') ######################## pacemaker
    next
  }
  setwd(d) # go to plate folder
  cleanup <- list.files() %>% grep('data', .,invert = T, value = T) # create list of files/folders other than data to delete
  unlink(cleanup, recursive = T, force = T) # delete the files
  setwd('data') # go to data folder
  # remove excess data:
  all_files <- list.files()
  files_to_remove1 <- all_files %>% grep('\\.tif$', ., invert = T, value = T) # non-image files
  files_to_remove2 <- all_files %>% grep('(DCP1A|_zMaxZ|_zMaxBkg)\\.tif', ., value = T) # non-projection images of DCP1A
  #files_to_remove3 <- all_files %>% grep('P0000[1-3]', ., value = T) # positions 1-3
  files_to_remove <- union(files_to_remove1, files_to_remove2) # collate
  if (length(files_to_remove) != 0) file.remove(files_to_remove) # delete the files
  
  remaining_files <- setdiff(all_files, files_to_remove) # list all remaining files
  if (length(remaining_files) == 0) {setwd('../..'); next} # if no files left, go to next plate
  
  # rename files to reorder tiles in montage and add plate number
  file.rename(from = remaining_files, to = paste(d, change_file_names(remaining_files), sep = '--'))
  
  cat(format(Sys.time()), '\t', 'plate done \n') ######################## pacemaker
  setwd('../..') # return to S drive
  processing_log <- append(d, processing_log) # log that the plate has been processed
  save(processing_log, file = 'processing_log.rda') # save list of plates that have already been processed
}

end_time <- Sys.time()
difftime(end_time, start_time, units = 'hours') %>% as.numeric

# this is for putting all files in a single folder
# to_bash <-
#   plates %>%
#   paste0('mv ', ., '/data/* collected_images && rm -r ', ., collapse = ' && ') %>% 
#   paste('mkdir collected_images', ., sep = ' && ')
# this is for keeping files in plate folders, all channels together
# to_bash <- plates %>% paste('cd', ., '&& mv data/* . && rmdir data && cd ..') %>% paste(., collapse = ' && ')
# cat('go to a Unix terminal, go to the master directory and execute the following command: \n')
# cat(to_bash)

cat('\n\ncongratulations \n#########################\n\n\n')
sink()

stop(call. = F)

# check for missing images and copy dummy files, if needed
setwd('C:/Users/Olek/Desktop/R works/')

setwd('S:/S14_copy/')
# list directories
dirs <- list.dirs(full.names = F, recursive = F)
dirs <- dirs[-67] # exclude some
# count files in each directory
file_counts <- sapply(dirs, function(x) length(list.files(path = paste0(x, '/data/'))))
# check which folders contain less than the highest number of files
problematic <- file_counts[file_counts != max(file_counts)]
# find wells with images missing
for (e in names(problematic)) {
  f <- list.files(path = paste0(e, '/data'), pattern = 'tif$')
  faulty_wells <- f %>% strsplit(., '--') %>% sapply(function(x) x[1]) %>% table %>% .[. != max(.)]
  print(e)
  print(faulty_wells)
}
# upgrade:
# function that counts images per well and returns wells were some are missing
Function <- function(x) {
  files_present <- list.files(path = paste0(x, '/data'), pattern = 'tif$')
  strsplit(files_present, '--') %>% sapply(function(x) x[1]) %>% table %>% .[. != max(.)]
  sth1 <- sapply(files_present, function(x) strsplit(x, '--')[1][[1]][1])
  well_occurrences <- table(sth1)
  well_occurrences[well_occurrences != max(well_occurrences)]
}
# apply it over problematic plates
sapply(problematic, Function, simplify = FALSE)

# which folders are they
names(problematic)[2]

# get a complete list of files (the way it should be) - from a complete plate!
p <- '089C.20180802.S12.R01'
files <- list.files(path = paste0(plate, '/data'))
full_complement <- files %>% gsub(p, '', .) %>% gsub('^--', '', .)

# ge tlist of files for a given plate
plate <- plates[1]
files <- list.files(path = paste0(plate, '/data')) %>% gsub(plate, '', .) %>% gsub('^--', '', .)
# get difference
missing_files <- setdiff(full_complement, files)
# copy dummy file in place of missing ones
file.copy('dummy.tif', paste0('C:/Users/Olek/Desktop/New folder/', plate, '--', missing_files))