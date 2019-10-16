/* Automatically build figures from ScanR images
 *  
 * Aleksander Chlebowski
 * Warsaw, 6 August 2019
 */

/* version 1.1
 * update 7 August 2019		added possibility of dropping channels (will be useful if saving projections)
 * version 1.2
 * update 21 August 2019	bug fixed in channel dropping functionality (dropping option was not being offered)
 *							enhanced default color offers
 * version 1.3
 * update 26 August 2019	added option of changing crop size (with defensives)
 *							zMaxZ channel are ignored automatically
 * version 2.0
 * update 4 September 2019	major overhaul
 *							added re-ordering panels
 *							added overlays (force re-ordering panels)
 *							added general montage
 *							added slide labels
 *							added channels labels (can't make them work on the left for the moment)
 *							montages are moved to "results" folder at the end"
 * version 2.1
 * update 5 September 2019	channel labels in overlays now appear in the same order as channels in the montage
 * version 2.2
 * update 6 September 2019	added option to limit the fields of view to use
 *							channel labels are now available on left side of the final montage
 *							minor corrections to label positioning
 *							added some defenses
 * version 2.3
 * update 9 September 2019	added option for renaming channels
 * 							added option to accept all images (no hand-picking)
 * 							added option to skip cropping images
 */


/*  This script substantially automates preparing figures from microscopy images obtained with a ScanR system (Olympus).
 *  
 *  It handles a master directory, which may contain several plate directories.
 *  All image files (.tif) in the master directory are listed.
 *  Non-images and previous results are ignored). 
 *  Channels are identified. Also: plates, wells and positions (fields of view).
 *  Colors are assigned to all channels. Channels can be dropped.
 *  The overall number of images can be limited by omitting some plates, wells or positions.
 *  
 *  Images are optionally pre-processed by applying blur or subtracting background.
 *  For every channel all images have their brightness adjusted to the same range.
 *  The images are converted to RGB and saved in a temporary directory, "master/temp".
 *  
 *  Subsequently, for each field of view all images (channels) are opened as a stack.
 *  Overlays are optinally constructed and panels are, also optionally, re-arranged in a specified order.
 *  The user is then asked to keep or discard the field of view from further processing.
 *  Kept fields of view are cropped to an area defined by the user.
 *  The cropped tiles are converted into a montage and saved in a second temporary directory, "master/tempm".
 *  Channel labels can be added at this stage.
 *  
 *  All montages are opened and optionally stamped with the name of the field of view.
 *  They are then converted into a single image, with optional scaling.
 *  Channel labels are optionally added on the right side.
 *  The final montage is saved as a .jpeg file in "master".
 *  Single montages are moved from "master/tempm" to "master/results".
 *  Temporary directories are removed.
 */


// get master directory
master = getDirectory("declare master directory ");
// delete possible old temp files
if (File.exists(master + "temp")) {print("cleaning up leftover temporary files"); remove(master + "temp");}
if (File.exists(master + "tempm")) {print("cleaning up more leftover temporary files"); remove(master + "tempm");}

// get list of all files
all_files = listFiles(master);
for (i = 0; i < all_files.length; i++) all_files[i] = replace(all_files[i], "\\", "/");

// get list of image files
image_files = keep(all_files, ".*\\.tif");
// drop files in "results" directory
image_files = drop(image_files, ".*results.*");

// get unique values for: plate (folder name), well (e.g. "A1"), position (field of view), and channel (e.g. "EGFP")
all_plates = newArray(image_files.length);
all_wells = newArray(image_files.length);
all_positions = newArray(image_files.length);
all_channels = newArray(image_files.length);
for (i = 0; i < image_files.length; i++) {
	image_path_split = split(image_files[i], "/--\\.");
	all_plates[i] = image_path_split[image_path_split.length-9];
	all_wells[i] = image_path_split[image_path_split.length-7];
	all_positions[i] = image_path_split[image_path_split.length-5];
	all_channels[i] = image_path_split[image_path_split.length-2];
}
plates = unique(all_plates);
wells = unique(all_wells);
positions = unique(all_positions);
channels_unique = unique(all_channels);
// drop zMaxZ channel, if present
channels = drop(channels_unique, ".*_zMaxZ.*");

// INPUT OPTIONS
Dialog.create("Opitons");
// assign colors to channels
colors_for_channels();
Dialog.addMessage("\n");
// option to rename channels
Dialog.addCheckbox("Rename channels", false);
Dialog.addMessage("\n");
// option for channel overlays
Dialog.addCheckbox("Channel overlays", false);
Dialog.addToSameRow(); Dialog.addNumber("how many?", 1);
Dialog.addMessage("\n");
// option for reordering panels
Dialog.addCheckbox("Set panel order", false);
Dialog.addMessage("\n");
// option for contrast
Dialog.addCheckbox("Set contrast automatically", true);
Dialog.addToSameRow(); Dialog.addSlider("or set saturation manually (0-99%):", 0, 100, 1);
Dialog.addMessage("\n");
// option for processing
process = Dialog.addCheckbox("Image pre-processing", false);
Dialog.addMessage("\n");
// crop size
Dialog.addNumber("Crop size (0 to skip cropping):", 512);
Dialog.addMessage("\n");
// montage options
Dialog.addMessage("Montage options:");
Dialog.addCheckbox("label slides", true);
Dialog.addRadioButtonGroup("label channels", newArray("no", "on left", "on right", "on each"), 1, 2, "on left");
Dialog.addCheckbox("panel borders", false);
Dialog.addToSameRow();
Dialog.addNumber("width", 0.01);
Dialog.addToSameRow();
Dialog.addChoice("color", newArray("black", "gray10", "gray25", "gray50", "gray75", "white"), "black");
Dialog.addNumber("scaling factor for general montage", 1);
Dialog.addMessage("\n");
// limit options
Dialog.addMessage("There are " + plates.length + " plates , " + 
                                 wells.length + " wells, and " + 
                                 positions.length + " positions, which makes for " + 
                                 plates.length * wells.length * positions.length + " fields of view.");
Dialog.addRadioButtonGroup("How to proceed?", newArray("pick from all", "pick from subset", "accept all"), 1, 3, "pick from all");
Dialog.show();

// RECEIVE INPUT
channel_colors = colors_for_channels_returned();
rename_channels = Dialog.getCheckbox();
overlay = Dialog.getCheckbox();
overlays = Dialog.getNumber();
reorder = Dialog.getCheckbox();
autocontrast = Dialog.getCheckbox();
saturation = Dialog.getNumber();
if (autocontrast) saturation = 100;
process = Dialog.getCheckbox();
crop_size = Dialog.getNumber();
// montage options
slide_labels = Dialog.getCheckbox();
channel_labels = Dialog.getRadioButton();
borders = Dialog.getCheckbox();
border_width = Dialog.getNumber() * borders;
border_color = Dialog.getChoice();
scale_factor = Dialog.getNumber();
procedure = Dialog.getRadioButton();
if (procedure == "accept all") useornot = true;

// defenses just in case
	// 1a. crop size: eliminate fractions, halt if size is suspect
	crop_size = floor(crop_size);
	if (crop_size == 0) {			crop = false;
	} else if (crop_size < 2) {		exit("ERROR: Crop size is too small.");
	} else if (crop_size < 25) {	showMessageWithCancel("WARNING", 
											"Crop size is oddly small (" + crop_size + "x" + crop_size + " px).\nContinue?");
											copr = true;
	} else {
		crop = true;
	}
	// 1b. check whether cropping area fits in images
	open(image_files[0]);
	getDimensions(wid, hei, cha, sli, fra);
	close();
	if (!crop) crop_size = wid;	// this is a dummy value; font size for labels is determined based on crop size
	if (crop) if (wid < crop_size || hei < crop_size) exit("Cropping area is too large.");
	// 2. montage: make sure scaling is not negative
	if (scale_factor <= 0) scale_factor = 1; // in case of stupid input
	if (scale_factor >= 1) scale_factor = 1; // in case of stupid input

// drop channels that were assigned no color
dropped_channels = which(channel_colors, "none");
kept_channels = flipBoolean(dropped_channels);
channels = subset(channels, kept_channels);
channel_colors = subset(channel_colors, kept_channels);
if (channels.length == 0) exit("ERROR: No channels left.");

// RENAMING CHANNELS (OPTIONAL)
if (rename_channels) channel_names = get_channel_names(channels); else channel_names = channels;

// OVERLAY INPUT (OPTIONAL)
if (overlay) {
	Dialog.create("Overlay options");
	for (i = 0; i < overlays; i++) {
		Dialog.addMessage("overlay " + i+1);
		Dialog.addMessage("select channels and assign colors");
		for (c = 0; c < channels.length; c++) {
			Dialog.addCheckbox(channels[c], false);
			Dialog.addToSameRow();
			suggest_color(channels[c]);
		}
	}
	Dialog.show();

	include_in_overlays = newArray(overlays * channels.length);
	for (i = 0; i < include_in_overlays.length; i++) include_in_overlays[i] = Dialog.getCheckbox();
	colors_in_overlays = newArray(overlays * channels.length);
	for (i = 0; i < colors_in_overlays.length; i++) colors_in_overlays[i] = Dialog.getChoice();

	olays = newArray(overlays);
	for (i = 0; i < overlays; i++) {
		olays[i] = "overlay-" + i+1;
		// check that this overlay contains at least one channel
		include_here = Array.slice(include_in_overlays, channels.length * i, channels.length * (i+1));
		if (sum(include_here) == 0) exit("ERROR in overlay definition\n" + olays[i] + " contains no channels");
	}
	panels = Array.concat(channels, olays);
} else {
	panels = Array.copy(channels);
	include_in_overlays = newArray("");
	colors_in_overlays = newArray("");
}

// SET PANEL ORDER (OPTIONAL)
if (overlay || reorder) panel_order = set_panel_order(panels); else panel_order = Array.getSequence(panels.length);
panels = filter(panels, panel_order);

// INPUT PROCESSING (OPTIONAL)
if (process) processing_options_input(channels);
// RECEIVE PROCESSING OPTIONS
processing_options = processing_options_returned(channels, process);
blur_mode = Array.slice(processing_options, 0, channels.length);
blur_radius = Array.slice(processing_options, channels.length, 2 * channels.length);
background_radius = Array.slice(processing_options, 2 * channels.length, 3 * channels.length);

// INPUT LIMITS (OPTIONNAL)
if (procedure == "pick from subset") {
	limits_input();
	limits = limits_received();
	limit_plates = Array.slice(limits, 0, plates.length);
	limit_wells = Array.slice(limits, plates.length, plates.length + wells.length);
	limit_positions = Array.slice(limits, plates.length + wells.length, limits.length);
	 // APPLY LIMITS
	plates = subset(plates, limit_plates);
	wells = subset(wells, limit_wells);
	positions = subset(positions, limit_positions);
	if (plates.length == 0) exit("ERROR: No plates selected.");
	if (wells.length == 0) exit("ERROR: No wells selected.");
	if (positions.length == 0) exit("ERROR: No positions selected.");
}

// END INPUT











// make brand new empty "temp" directory
File.makeDirectory(master + "temp/");
// make brand new empty "tempm" directory
File.makeDirectory(master + "tempm/");

////////////////////////////
//// PART ONE: CONTRAST ////
////////////////////////////
/* for each channel
	open all images of a channel
	pre-process (optional)
	set brightness
	convert to RGB
	save images in temp directory
*/
for (c = 0; c < channels.length; c++) {
	open_channel(image_files, channels[c]);
	// image processing
	if (process) {
		if (blur_mode[c] != "none") run(blur_mode[c], blur_radius[c] + " stack");
		if (background_radius[c] != 0) run("Subtract Background...", "rolling=" + background_radius[c] + " stack");
	}
	// set contrast
	adjust_contrast(saturation);
	// apply color and convert to RGB
	make_LUT(channel_colors[c]);
	run("RGB Color");
	// save in temp
	run("Image Sequence... ", "format=TIFF name=Stack use save=" + master + "temp/" + "Stack0000.tif");
	close();
}

///////////////////////////
//// PART TWO: FIELDS /////
///////////////////////////

// create list of combinations of plate and well
patterns = newArray();
for (s = 0; s < plates.length; s++) {
	for (w = 0; w < wells.length; w++) {
		for (p = 0; p < positions.length; p++) {
			patterns = Array.concat(patterns, plates[s] + ".*" + wells[w] + ".*" + positions[p] + ".*");
		}
	}
}

fields = newArray();
for (p = 0; p < patterns.length; p++) {
	// create overlays, if requested
	if (overlay) {
		for (o = 0; o < overlays; o++) {
			// which channels to include in this overlay
			include_here = Array.slice(include_in_overlays, channels.length * o , channels.length * (o+1));
			if (sum(include_here) == 0) continue;
			// what colors to assign in this overlay
			colors_here = Array.slice(colors_in_overlays, channels.length * o , channels.length * (o+1));

			// open requested channels, convert to 8-bit, assign LUT
			for (inc = 0; inc < channels.length; inc++) {
				if (include_here[inc]) {
					P = patterns[p] + channels[inc] + ".*";
					run("Image Sequence...", "open=" + master + "temp/image.tif file=(" + P + ")");
					rename(File.nameWithoutExtension);
					run("8-bit");
					make_LUT(colors_here[inc]);
				} else continue;
			}
			// merge
			// get titles of open windows
			images = getList("image.titles");
			// merging option is created as array
			option_array = newArray(images.length + 1);
			// strings designate all open images as channel in coposite
			for (i = 0; i < images.length; i++) option_array[i] = "c" + i+1 + "=" + images[i];
			// additional options are added at the end
			option_array[images.length] = "create keep";
			// the array is combined into a single string with custom function
			option_for_merge = unsplit(option_array, " ");			
			// merge; composite is created
			run("Merge Channels...", option_for_merge);
			// convert composite to RGB (new window created)
			run("RGB Color");
			// save composite; replace any channel name in file name with overlay name
			olay_name = replace(File.name, unsplit(channels, "|"), olays[o]);
			saveAs(".tif", master + "temp/" + olay_name);
			// close all windows
			close("*");
		}
	}
	// overlays complete
	
	// open panels one by one (in order), rename, and wrap into stack
	for (i = 0; i < panels.length; i++) {
		P = patterns[p] + panels[i] + ".*";
		run("Image Sequence...", "open=" + master + "temp/image.tif file=(" + P + ")");
		if (i < 10) rename("panel-0" + i+1); else rename("panel-" + i+1);
	}
	if (nImages > 1) run("Images to Stack");
	// draw cropping area and ask user whether to use this field
	if (crop) makeRectangle(floor(wid/2 - crop_size/2), floor(hei/2 - crop_size/2), crop_size, crop_size);
	if (procedure != "accept all") useornot = getBoolean("use this image?" + "\n" + 
		                                                 "(" + (p + 1) + " of " + patterns.length + ")", "yes", "no");
	if (useornot) {
		 //	add this field to list of inclued fields (used for file names later) 
		thisfield = replace(patterns[p], "\\.\\*", "--");
		thisfield = replace(thisfield, "--$", "");
		fields = Array.concat(fields, thisfield);
		if (crop) {
			// wait for user to set cropping area
			waitForUser("select region to crop but\nDO NOT MODIFY the selection dimensions!");
			run("Crop");
			// check if the image is cropped correctly and backtrack if not
			Stack.getDimensions(width, height, chann, slices, frames);
			if (width != crop_size || height != crop_size) {
				showMessage("ERROR", "Cropped image has wrong dimensions and will be reloaded.");
				close("*");
				p--;
				continue;
			}
		}
		// make montage
		// determine border width (in pixels) based on input and image dimensions
		Stack.getDimensions(width, height, chann, slices, frames);
		if (border_width != 0 && border_width <= 1) border_width = floor(border_width * width);
		// set foreground color for panel borders
		fg_color(border_color);
		// make and save montage
		option = "columns=" + slices + " rows=1 scale=1 border=" + border_width + " use";
		if (nSlices > 1) run("Make Montage...", option);
		// add channel labels, if requested for each field
		if (channel_labels == "on each") {
			label_panels(channels, channel_colors, channel_names, panels,
			             include_in_overlays, colors_in_overlays,
			             crop_size, border_width, 1);
		}
		saveAs("tiff", master + "tempm/" + thisfield + ".tif");
		close("*");
		
	} else {
		// close image and move on to next field
		close();
		continue;
	}
}

/////////////////////////////////////
//// PART THREE: OVERALL MONTAGE ////
/////////////////////////////////////

if (fields.length == 0) {
	// move montages from master/tempm to master/results
	File.makeDirectory(master + "results/");
	copy_all(master + "tempm", master + "results");
	// remove temporary directories
	remove(master + "temp");
	remove(master + "tempm");
	exit("No fields selected. I guess we're done, then.");
}

// prepare for drawing slide labels, if requested
if (slide_labels) {
	font_size = floor(crop_size / 30);
	setJustification("left");
	setColor("white");
	setFont("Monospace", font_size);
	coordinate = floor(crop_size / 30);
	coordinate_x = floor(coordinate / 4); coordinate_y = floor(coordinate * 1.1);
}

// open all saved fields
for (i = 0; i < fields.length; i++) {
	open(master + "tempm/" + fields[i] + ".tif");
	run("Rotate 90 Degrees Right");
	// add slide labels, if requested
	if (slide_labels) {
		drawString(fields[i], coordinate, coordinate, "black");
	}
}

if (nImages == 1) {
	run("Scale...", "x=" + scale_factor + " y=" + scale_factor + " z=1.0 " + 
                    "width=" + crop_size * scale_factor + " height=" + crop_size * scale_factor + 
                    " interpolation=Bicubic average create title=scaled");
	close("\\Others");
} else {
	// make montage
	run("Images to Stack");
	fg_color(border_color);
	// make montage, save it and close all images
	option_for_montage = "columns=" + fields.length + " rows=1 scale=" + scale_factor + 
	                     " border=" + floor(border_width * scale_factor) + " use";
	run("Make Montage..." , option_for_montage);
}

// add channel labels on one side, if requested
if (channel_labels == "on left") {
	// adjust some objects for reverse panel order
	Array.reverse(channels);
	Array.reverse(channel_colors);
	Array.reverse(panels);
	Array.reverse(include_in_overlays);
	Array.reverse(colors_in_overlays);
	// done
	run("Rotate 90 Degrees Right");
	label_panels(channels, channel_colors, channel_names, panels,
	             include_in_overlays, colors_in_overlays,
	             crop_size, border_width, scale_factor);
	run("Rotate 90 Degrees Left");
} else if (channel_labels == "on right") {
	run("Rotate 90 Degrees Left");
	label_panels(channels, channel_colors, channel_names, panels,
	             include_in_overlays, colors_in_overlays,
	             crop_size, border_width, scale_factor);
	run("Rotate 90 Degrees Right");
}

// save as jpeg
saveAs(".jpg", master + "general_montage.jpg");

// close all images
close("*");

// move montages from master/tempm to master/results
File.makeDirectory(master + "results/");
copy_all(master + "tempm", master + "results");
// remove temporary directories
remove(master + "temp");
remove(master + "tempm");

open(master + "general_montage.jpg");

exit("done");






//////////////////////////////
//// FUNCTION DEFINITIONS ////
//////////////////////////////

function colors_for_channels() {
	// prepare list of choices
	colors = newArray("none", "red", "green", "blue", "cyan", "magenta", "yellow", "gray", "redish", "greenish", "blueish", "yellowish");
	Dialog.addMessage("Select colors for channels\n");
	//Dialog.addMessage("(selecting \"none\" will cause the channel to be omitted)");
	for (c = 0; c < channels.length; c++) {
		if (matches(channels[c], ".*Hoechst.*")) {col = "blueish";
		} else if (matches(channels[c], ".*EGFP.*")) {col = "greenish";
		} else if (matches(channels[c], ".*mCherry.*")) {col = "redish";
		} else if (matches(channels[c], ".*405.*")) {col = "blue";
		} else if (matches(channels[c], ".*488.*")) {col = "greenish";
		} else if (matches(channels[c], ".*555.*")) {col = "redish";
		} else if (matches(channels[c], ".*647.*")) {col = "magenta";
		} else col = "gray";
		Dialog.addChoice("channel: " + channels[c], colors, col);
	}
}

function colors_for_channels_returned() {
	// collect color choices
	channel_colors = newArray(channels.length);
	for (c = 0; c < channels.length; c++) channel_colors[c] = Dialog.getChoice();
	return channel_colors;
}

function suggest_color(channel) {
	// prepare list of choices
	colors = newArray("red", "green", "blue", "cyan", "magenta", "yellow", "gray", "redish", "greenish", "blueish", "yellowish");
	if (matches(channel, ".*Hoechst.*")) {col = "blueish";
	} else if (matches(channel, ".*EGFP.*")) {col = "greenish";
	} else if (matches(channel, ".*mCherry.*")) {col = "redish";
	} else if (matches(channel, ".*405.*")) {col = "blue";
	} else if (matches(channel, ".*488.*")) {col = "greenish";
	} else if (matches(channel, ".*555.*")) {col = "redish";
	} else if (matches(channel, ".*647.*")) {col = "magenta";
	} else col = "gray";

	Dialog.addChoice("", colors, col);
}

function set_panel_order(array) {
	// array contains channel names (as strings)
	// put up dialog window
	Dialog.create("Set panel order (left to right)");
	Dialog.addMessage("Assign position numeral to each channel.");
	for (i = 0; i < array.length; i++) Dialog.addNumber("panel position for : " + array[i] + " (1-" + array.length + ")", i+1);
	Dialog.show();
	// capture input
	panel_positions = newArray(array.length);
	for (i = 0; i < array.length; i++) {
		panel_positions[i] = Dialog.getNumber();
	}
	// check if indices are unique
	if (anyduplicates(panel_positions)) exit("ERROR: panel positions must be unique");
	// check if indices are in proper range
	if (minimum(panel_positions) < 1 || maximum(panel_positions) > array.length) {
		exit("ERROR: panel positions MUST be from 1 through " + array.length);
	}
	// checks done
	ordered = newArray();
	for (i = 1; i <= panel_positions.length; i++) {
		element = whichfirst(panel_positions, i);
		ordered = Array.concat(ordered, element);
	}
	
	return ordered;
}

function processing_options_input(array) {
	// array contains channel names
	Dialog.create("Advanced options");
	for (c = 0; c < array.length; c++) {
		if (c == 0)	Dialog.addMessage("select blur mode, blur radius and background subtraction radius");
		Dialog.addChoice("channel " + array[c], newArray("none", "Gaussian Blur", "Median"), "none");
		Dialog.addToSameRow();
		Dialog.addNumber("", 1.5);
		Dialog.addToSameRow();
		if (array[c] == "DCP1A" || array[c] == "J2" || array[c] == "BrU") defrad = 2; else defrad = 85;
		Dialog.addNumber("", defrad);
	}
	Dialog.show();
}

function processing_options_returned(array, change) {
	// set defaults: all nones and zeros
	blur_mode = newArray(array.length); for (i = 0; i < array.length; i++) blur_mode[i] = "none";
	blur_radius = newArray(array.length); for (i = 0; i < array.length; i++) blur_radius[i] = 0;
	background_radius = newArray(array.length); for (i = 0; i < array.length; i++) background_radius[i] = 0;
	
	if (change) {
		for (c = 0; c < array.length; c++) {
			blur_mode[c] = Dialog.getChoice();
			blur_radius[c] = Dialog.getNumber();
			background_radius[c] = Dialog.getNumber();
		}
		for (c = 0; c < array.length; c++) {
			if (blur_mode[c] != "none") blur_mode[c] = blur_mode[c] + "...";
			if (blur_mode[c] == "Gaussian Blur...") prefix = "sigma="; else prefix = "radius=";
			blur_radius[c] = prefix + blur_radius[c];
		}
	}
	processing_options = Array.concat(blur_mode, blur_radius, background_radius);
	return processing_options;
}

function limits_input() {
	Dialog.create("Limits");
	Dialog.addMessage("Select features to include.");
	Dialog.addMessage("plates:");
	for (i = 0; i < plates.length; i++) {
		Dialog.addCheckbox(plates[i], false);
		if (floor((i+1)/12) != (i+1)/12) Dialog.addToSameRow();
	}
	Dialog.addMessage("");
	Dialog.addMessage("wells:");
	for (i = 0; i < wells.length; i++) {
		Dialog.addCheckbox(wells[i], false);
		if (floor((i+1)/12) != (i+1)/12) Dialog.addToSameRow();
	}
	Dialog.addMessage("");
	Dialog.addMessage("positions:");
	for (i = 0; i < positions.length; i++) {
		Dialog.addCheckbox(positions[i], false);
		if (floor((i+1)/12) != (i+1)/12) Dialog.addToSameRow();
	}
	Dialog.addMessage("");
	Dialog.show();
}

function limits_received() {
	Plates = newArray(plates.length);
	for (i = 0; i < Plates.length; i++) Plates[i] = Dialog.getCheckbox();
	Wells = newArray(wells.length);
	for (i = 0; i < Wells.length; i++) Wells[i] = Dialog.getCheckbox();
	Positions = newArray(positions.length);
	for (i = 0; i < Positions.length; i++) Positions[i] = Dialog.getCheckbox();

	limits = Array.concat(Array.concat(Plates, Wells), Positions);
	return limits;
}





function open_channel(filelist, channel) {
	pattern = ".*" + channel + ".*";
	for (i = 0; i < filelist.length; i++) {
		if (matches(filelist[i], pattern)) {
			open(filelist[i]);
			file_path_split = split(filelist[i], "/");
			rename(file_path_split[file_path_split.length-3] + "--" + file_path_split[file_path_split.length-1]);
		}
	}
	run("Images to Stack");
}


/* set contrast (min and max value) for open image or stack
 * argument saturation	percentage points of pixels that are to be saturated
 * set saturation to 100 to use histogram statistics:
 * 	min = mean - Stdev
 * 	max = mean + 10 * Stdev
 */
function adjust_contrast(saturation) {
	if (saturation == 100) {
		// use histogram statistics
		getRawStatistics(voxelCount, mean, min, max, stdDev);
		low = floor(mean - stdDev);
		high = floor(mean + 10 * stdDev); 
	} else {
		option_for_contrast = "saturated=" + saturation;
		run("Enhance Contrast", option_for_contrast);
		getMinAndMax(min, max);
		low = min;
		high = max;
	}
	setMinAndMax(low, high);
}

function label_panels(channels, channel_colors, channel_labels, panels, 
                      overlay_inclusion, overlay_colors, 
                      panel_width, border_width, scale_factor) {
/* arguments:
 *  channels			array containing names of channels
 *  channel_colors		array containing names of colors to assign to channels; returned by colors_for_channels_returned
 *  channel_labels		array containing label for channels
 *  panels				array containing names of panels, as they appear in the figure (in order)
 *  overlay_inclusion	logical array that determines which channel to include to which overlay
 *  overlay_colors		array containing colors assigned to channels in overlays
 *  panel_width			width of individual panel, in pixels
 *  border width		width of montage border, in pixels
 *  scale_factor		scaling factor that was used when making the current montage
 */

	// determine label placement and font size and format
	coordinate = floor(panel_width / 20 * scale_factor);
	coordinate_x = floor(coordinate / 4); coordinate_y = floor(coordinate * 1.1);
	font_size = floor(panel_width / 20 * scale_factor);
	setFont("Monospace", font_size , "bold");
	setJustification("left");

	for (p = 0; p < panels.length; p++) {
		panel = panels[p];
		// overlays are a little more complicated
		if (matches(panel, "overlay.*")) {
			// get overlay number
			o = replace(panel, "overlay-", ""); o = parseInt(o); o--;
			// which channels to include in this overlay
			include_here = Array.slice(overlay_inclusion, channels.length * o , channels.length * (o+1));
			// what colors to assign in this overlay
			colors_here = Array.slice(overlay_colors, channels.length * o , channels.length * (o+1));
			// pick out the things that go in this panel
			labels_here = subset(channels, include_here);
			colors_here = subset(colors_here, include_here);
			// rearrange so that labels appear in the same order as channels in montage
			ind = order(labels_here, panels);
			labels_rearranged = filter(labels_here, ind);
			colors_rearranged = filter(colors_here, ind);
			// end rearrange
			// apply labels
			for (l = labels_rearranged.length-1; l >= 0 ; l--) {
				// pick color
				color = colors_rearranged[l]; color = make_color(color); setColor(color);
				// translate channel name to label
				ind = whichfirst(channels, labels_rearranged[l]);
				label = channel_labels[ind];
				// draw label
				drawString(label, coordinate_x + (p * scale_factor * (panel_width + border_width)),
				                  coordinate_y * (l+1), "black");
			}
			continue;
		}
		// pick color with the same index as the channel that matches the current label
		ind = whichfirst(channels, panel);
		label = channel_labels[ind];
		color = channel_colors[ind]; color = make_color(color); setColor(color);
		// draw label
		drawString(label, coordinate_x + (p * scale_factor * (panel_width + border_width)), coordinate_y, "black");
	}
}

function get_channel_names(array) {
	Dialog.create("Ascribe new names to channels");
	for (i = 0; i < array.length; i++) Dialog.addString("new name for channel " + array[i] + ":", array[i]);
	Dialog.show();

	newarray = newArray(array.length);
	for (i = 0; i < array.length; i++) newarray[i] = Dialog.getString();

	return newarray;
}
