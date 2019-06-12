/* by Aleksander Chlebowski 
 * Warsaw, 29 January 2019
 * 
 * Take grayscale images that represent montages of whole screening plates and combine them into multi-color images.
 * 
 */
 
// update	6 February 2019		check for missing images at each plate; if so, omit and give a warning

// declare target and master directories
master = getDirectory("Declare master directory");
// create target directory for storing the plate views
target_directory = master + "plate views in color/";
if (!File.exists(target_directory)) File.makeDirectory(target_directory);

print("getting file list");
// get list of images (files excluding directories)
all_files = getFileList(master + "plate views/");
file_list = newArray(0);
for (f = 0; f < all_files.length; f++) if (!endsWith(all_files[f], "/")) file_list = Array.concat(file_list, all_files[f]);

// isolate plate and channel names from file names
print("detecting plates and channels");
all_plates = newArray(file_list.length);
for (f = 0; f < file_list.length; f++) {
	filename_split = split(file_list[f], "_");
	all_plates[f] = filename_split[0];
}
all_channels = newArray(file_list.length);
for (f = 0; f < file_list.length; f++) {
	filename_split = split(file_list[f], "_.");
	all_channels[f] = filename_split[filename_split.length-2];
}
// get uniques
plates = unique(all_plates);
channels = unique(all_channels);

// INPUT OPTIONS (assign colors to channels
// prepare list of choices
colors = newArray("none", "red", "green", "blue", "cyan", "magenta", "yellow", "gray", "redish", "greenish", "blueish", "yellowish");
Dialog.create("Select colors for channels");
Dialog.addMessage("selecting \"none\" will cause channel to be omitted");
for (c = 0; c < channels.length; c++) {
	if(channels[c] == "DCP1A") {col = "blue";
	} else if (channels[c] == "EGFP") {col = "greenish";
	//} else if (matches(channels[c], "gfp")) {col = "greenish";	// test for flexible channel name identification
	} else if (channels[c] == "mCherry") {col = "redish";
	//} else if (matches(channels[c], "cherry")) {col = "redish";			// test
	} else col = "none";
	Dialog.addChoice("channel: " + channels[c], colors, col);
}
Dialog.show();
// collect color choices
channel_colors = newArray(channels.length);
for (c = 0; c < channels.length; c++) channel_colors[c] = Dialog.getChoice();
// which channels to include (the ones colored "none" will be omitted
channel_include = newArray(channels.length);
for (c = 0; c < channels.length; c++) if (channel_colors[c] == "none") channel_include[c] = false; else channel_include[c] = true;
// in case of stupid
if (sum(channel_include) == 0) exit("ERROR: no channels included in composite\nyou must select a color for at least two channels");
if (sum(channel_include) == 1) exit("ERROR: only one channel included in composite\nyou must select a color for at least two channels");
// stupidity covered
// INPUT COMPLETE


print("commencing coloring");
for (p = 0; p < plates.length; p++) {
	// get plate name
	plate = plates[p];
	print(" beginning work on plate " + plate);
	final_file = target_directory + plate + "_multicolor" + ".tif";
	if(File.exists(final_file)) {print("  this one is already done"); continue}

	// open all files for a given plate
	run("Image Sequence...", "open=[" + master + "plate views/] file=" + plate + " sort use");
	
	// check for missing images and skip plate if any
	if (nSlices != channels.length) {
		print("  WARNING: this plate has images missing!");
		print("  plate omitted");
		continue;
	}
	
	// split into individual images
	run("Stack to Images");
	// get names of open windows
	panels = getList("image.titles");
	// apply selected colors to channels
	for (i = 0; i < panels.length; i++) {
		selectWindow(panels[i]);
		make_LUT(channel_colors[i]);
	}
	// commence merging
	// merging option is created as array
	option_array = newArray(channels.length + 1);
	// included channels get pasted into strings, others just get a 0 (must be a string!)
	for (i = 0; i < channels.length; i++) {
		if (channel_include[i]) option_array[i] = "c" + i+1 + "=" + panels[i]; else option_array[i] = "0";
	}
	// additional option is added at the end: create composite (LUTs are ignored otherwise)
	option_array[channels.length] = "create";
	// the array is combined into a single string with custom function
	option_for_merge = unsplit(option_array, " ");
	// merge; composite is created
	run("Merge Channels...", option_for_merge);
	// convert composite to RGB (new window created) and rename it
	run("RGB Color");
	rename(plate);
	// save file and close all windows
	saveAs("Tiff", final_file);
	close("*");
	print("  plate done");
}
print("that was the last one");
exit("finished");

////////////////////////////////
///// FUNCTION DEFINITIONS /////
////////////////////////////////

function unique_ac(array) {
	uniques = Array.trim(array, 1);
	for (i = 1; i < array.length; i++) {
		previous = Array.trim(array, i);
		j = 0;
		while (j <= i) {
			if (i == j) {
				uniques = Array.concat(uniques, array[i]);
				break;
			} else if (array[i] == previous[j]) {
				break;
			}
		j++;
		}
	}
	return uniques;
}

function unique(array) {
	sorted = Array.sort(array);
	uniques = Array.trim(sorted, 1);
	for (i = 1; i < array.length; i++) {
		if (sorted[i] != sorted[i-1]) uniques = Array.concat(uniques, array[i]);
	}
	return uniques;
}

function all(array) {
// check whether all elements of array are true
	for (i = 0; i < array.length; i ++) if (!array[i]) return(false);
	return true;
}

function any(array) {
// check whether any element of a array is true
	for (i = 0; i < array.length; i ++) if (array[i]) return(true);
	return false;
}

function sum(array) {
// return sum of all elements of array
	s = 0;
	for (i = 0; i < array.length; i++) s = s + array[i];
	return s;
}

function make_LUT(color) {
// set a monochromatic LUT

// by default the LUT will be "Gray"
	reds = newArray(256); greens = newArray(256); blues = newArray(256);
	for (i=0; i<256; i++) { reds[i] = i; greens[i] = i; blues[i] = i; }
// standard colors
	if (color == "Red" || color == "red" || color == "#ff00") {
    	for (i=0; i<256; i++) { reds[i] = i; greens[i] = 0; blues[i] = 0; }
	} else if (color == "Green" || color == "green" || color == "#0ff0") {
    	for (i=0; i<256; i++) { reds[i] = 0; greens[i] = i; blues[i] = 0; }
	} else if (color == "Blue" || color == "blue" || color == "#00ff") {
    	for (i=0; i<256; i++) { reds[i] = 0; greens[i] = 0; blues[i] = i; }
	} else if (color == "Cyan" || color == "cyan" || color == "#0ffff") {
    	for (i=0; i<256; i++) { reds[i] = 0; greens[i] = i; blues[i] = i; }
	} else if (color == "Magenta" || color == "magenta" || color == "#ff0ff") {
    	for (i=0; i<256; i++) { reds[i] = i; greens[i] = 0; blues[i] = i; }
	} else if (color == "Yellow" || color == "yellow" || color == "#ffff0") {
    	for (i=0; i<256; i++) { reds[i] = i; greens[i] = i; blues[i] = 0; }
	} else if (color == "Hi-Lo" || color == "HiLo" || color == "hi-lo" || color == "hilo") {
    	for (i=0; i<256; i++) { reds[i] = i; greens[i] = i; blues[i] = i; blues[0] = 255; greens[255] = 0; blues[255] = 0; }
	}
	// custom colours
	else if (color == "Hoechst" || color == "hoechst" || color == "DNA" || color == "#3faaff") {
    	for (i=0; i<256; i++) { reds[i] = floor(i * 1/4); greens[i] = floor(i * 2/3); blues[i] = i; }
	} else if (color == "Blue-ish" || color == "blue-ish" || color == "Blueish" ||color == "blueish" || color == "#3faaff") {
    	for (i=0; i<256; i++) { reds[i] = floor(i * 1/4); greens[i] = floor(i * 2/3); blues[i] = i; }
	} else if (color == "Yellow-ish" || color == "yellow-ish" || color == "Yellowish" ||color == "yellowish" || color == "#ffff3f") {
    	for (i=0; i<256; i++) { reds[i] = i; greens[i] = i; blues[i] = floor(i * 1/4); }
	} else if (color == "Green-ish" || color == "green-ish" || color == "Greenish" ||color == "greenish" || color == "#0ff55") {
    	for (i=0; i<256; i++) { reds[i] = 0; greens[i] = i; blues[i] = floor(i * 1/3); }
	} else if (color == "Red-ish" || color == "red-ish" || color == "Redish" || color == "redish" || color == "#ff3333") {
	    for (i=0; i<256; i++) { reds[i] = i; greens[i] = floor(i * 1/5); blues[i] = floor(i * 1/5); }
	}

	setLut(reds, greens, blues);
}

function unsplit(arr, sep) {
//concatenate elements of array with separator
	x = arr;
	y = x[0];
	for (i = 1; i < x.length; i++) y = y + sep + x[i];
	return y;
}

