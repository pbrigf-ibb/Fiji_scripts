/* By Aleksander Chlebowski
 * Warsaw, 24 September 2018 
 * 
 * Script for putting together multiple timelapse files OR making easily viewable montages of XYZC stacks.
 * You may need to update ImageJ for it to run.
 * For safety, avoid spaces in paths.
 */


/* Some assumptions:
 * 1. Works with Olympus CSLM files (.oif and .oib).
 * 2. There is a transmitted light channel and it is the last one.
 * 3. All files are either XY(Z)CT with the same XYCT dimensions, or XYZC stacks with all the same dimensions.
 * 4. The script can handle up to 7 channels.
 * 
 * What you will get:
 * 	Each channel will get a colour and these are set.
 * 		for XY(Z)CT stacks:
 * 			Only one Z slice will be selected and it will be the middle one.
 * 			Channels will be arranged vertically.
 * 			Slides will be arranged horizontally.
 * 			T stacks will be preserved.
 * 			The final file will be scaled down by a factor 0.5 to facilitate handling.
 * 		for XYCT stacks:
 * 			Channels will be arranged vertically.
 * 			Z stacks will be preserved.
 * 			XY dimensions will be preserved.
 * 			Files will be saved in the newly created "colored_stacks" directory.
 * 			The saved files will be RGB tiffs with the same names as the original files.
 * 			
 * What may be added in the future:
 * 	interactive channel colors
 * 	file name labels
 * 	channel name labels
 * 	choice of Z slice to pick in timelapse
 * 	projection instead of sinlge slice
 * 	
 */

// prepare channel colors
colors = newArray("Green", "Yellow", "Red", "Magenta", "Cyan", "Blue", "Grays");

Dialog.create("Welcome");
Dialog.addMessage("Documentation can be found within the source file.");
Dialog.addMessage("Find it: combining_stacks_.ijm");
Dialog.show();
// get master directory
master = getDirectory("Choose a directory:");
// create temp directory, if absent
if (!File.exists(master + "temp")) File.makeDirectory(master + "temp");
if (!File.exists(master + "color_stacks")) File.makeDirectory(master + "color_stacks");
// get file list
files = getFileList(master);

for (f = 0; f < files.length; f++) {
	// get name of particular file
	file = files[f];
	// if it's not an Olympus image file, skip
	if (!endsWith(file, "oib") && !endsWith(file, "oif")) continue
	// open file
	option = "open=" + master + File.separator + file + " autoscale color_mode=Default rois_import=[ROI manager] view=Hyperstack stack_order=XYCZT";
	run("Bio-Formats", option);
	// get stack dimensions to get number of channels
	getDimensions(width, height, channels, slices, frames);
	// trim colors array to channel number and change the last one to gray
	colors = Array.trim(colors, channels);
	colors[channels-1] = "Grays";
	
	// get window title
	window_title = getInfo("window.title");
	// check if this is a multislice, multiframe image (XYZT slice)
	if (frames > 1) MODE = "timelapse"; else MODE = "colors";
	// for timelapse images only:
	if (MODE == "timelapse") {
		if (slices > 1) {
			// duplicate middle slice
			option = "duplicate slices=" + floor(frames / 2 + 1);
			run("Duplicate...", "duplicate slices=2");
			// get window title
			window_title2 = getInfo("window.title");
			// close original window
			selectWindow(window_title);
			close();
			// go back to remaining window
			selectWindow(window_title2);
		}
	}
	// split channels
	run("Split Channels");
	// get names of all open windows (channels)
	window_names = getList("image.titles");
	// do the channel thing
	for (c = 0; c < channels; c++) {
		selectWindow(window_names[c]);
		if (c == channels-1) {
			if (MODE == "timelapse") {
				setMinAndMax(0, 2500);
				run("Apply LUT", "stack");
			} else {};
		} else {
			if (MODE == "timelapse") {
				setMinAndMax(100, 1000);
			} else if (MODE == "colors") {
				run("Enhance Contrast", "saturated=0.00");
			}
			run("Apply LUT", "stack");
			run("Median...", "radius=2 stack");
		}
		run(colors[c]);
		run("RGB Color");
	}

	// prepare options for combining files
	combining_options = newArray(channels-1);
	combining_options[0] = "stack1=" + window_names[0] + " stack2=" + window_names[1];
	for (co = 1; co < combining_options.length; co++) {
		combining_options[co] = "stack1=[Combined Stacks]" + " stack2=" + window_names[co+1];
	}
	// modify options for timelapse stacks: combining will be done vertically
	if (MODE == "timelapse") for (co = 0; co < combining_options.length; co++) combining_options[co] = combining_options[co] + " combine";
	// run the combining
	for (co = 0; co < combining_options.length; co ++) {
		run("Combine...", combining_options[co]);
	}
	// get image name by trimming the file extension
	image_name = File.nameWithoutExtension;
	// save file and close
	if (MODE == "timelapse") {
		option = master + "temp/" + image_name + ".tif";
	} else if (MODE == "colors") {
		option = master + "color_stacks/" + image_name + ".tif";
	}
	saveAs("Tiff", option);
	close();
}

// list files in temp directory
if (MODE == "timelapse") {
	temps = getFileList(master + "temp/");
	// for each T stack
	for (i = 0; i < temps.length; i++) {
		// open file
		open(master + "temp/" + temps[i]);
		// if this is the first file, get window title and move on
		if (i == 0) {
			s1 = getInfo("window.title");
			continue;
		}
		// get window title; this is the second window
		s2 = getInfo("window.title");
		// create option for combining windows
		if (i == 1) { // if this is the second file, include two file names
			combining_option = "stack1=" + s1 + " stack2=" + s2;
		} else { // otherwise include "Combined Stacks" and the latest file name
			combining_option = "stack1=" + "[Combined Stacks]" + " stack2=" + s2;
		}
		// combine
		run("Combine...", combining_option);
	}
	// scale down, save (in master directory) and close
	run("Scale...", "x=.5 y=.5 interpolation=Bilinear average process create title=combined_timelapses.tif");
	saveAs("Tiff", master + "combined_timelapses.tif");
	close("*");	
}


// delete temp directory
remove(master + "temp");
// delete color_stacks directory if empty
File.delete(master + "color_stacks");

exit("The end.");

///// FUNCTION DEFINITIONS /////
function remove(file) {
// delete a file or a nonempty directory (recursively)

	if (File.isDirectory(file)) {
		contents = getFileList(file);
		if (contents.length != 0) for (i = 0; i < contents.length; i++) {
			if (File.isDirectory(file + "/" + contents[i])) remove(file + "/" + contents[i]);
			File.delete(file + "/" + contents[i]);
		}		
	}
	File.delete(file);
}
