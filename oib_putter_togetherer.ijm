/* By Aleksander Chlebowski
 * Warsaw, September 2018
 */

// update 21 November 2018	bug fixes
// update 15 January 2019	bug fixes in make_color function

 
/* This is a script for preparing figures from confocal images.
 *  
 * It is written for z-stacks collected with Olympus software and saved in the .oib or .oif formats.
 * It is assumed that multiple channels are present. One of them may be transmitted light (hereafter referred to as DIC).
 * DIC channel must be specified by the user, if present.
 * 
 * Fluorescence channels will be converted into maximum intensity projections.
 * For DIC only one slice will be extracted. The slice will be chosen either as an option or as a specific slice number.
 * (IMPORTANT: it is asumed that z-stacks begin above the cell and end where the cell is attached to the glass.)
 * 
 * The script consists of four parts, which are nto entirely indepedent, i.e. some variables are used in down the line.
 * 
 * A number of functions are used throughout the sicript.
 * All function definitions are found at the end, after an exit() statement.
 * 
 */



/* WORKFLOW EXPLANATION
 * 
 * PART ZERO: File preparation.
 * Files are kept in a master directory.
 * The master directory should, but need not, contain the following subdirectories: input, temp, results, and rejects.
 * 	input		files will be loaded from here
 * 	temp		temporary files will be kept here (they will be deleted at the end)
 * 	results		all final files will end up here
 * 	rejects		you can put the files you want to omit here
 * If the subdirectories don't exist, they will be created and all .oib files will be moved to the input directory.
 * 
 * PART ONE: Z projections.
 * Each file is loaded, split into separate channels, and channel are treated accordingly.
 * Fluorescence channel are maxz-projected, one frame is selected form the DIC channel.
 * New images are saved in the temp directory.
 * Slide names are extracted from file names (extensions are stripped).
 * New files are named with slide names with channel numbers (1+) appended.
 * 
 * PART TWO: Contrast.
 * To enable consistent presentation, a common LUT will be applied to all images in each channel.
 * All images from a channel are loaded as stack, their (common) histogram is clipped by 0.25%.
 * Files will be-resaved in the temp directory.
 * 
 * PART THREE: Single montages.
 * A montage is created for each slide; single row, channels in columns.
 * Just in case the DIC channel is not the last one, it will be taken out of the stack and concatenated at the end.
 * Images are saved in .tiff format in the results directory.
 * 
 * PART FOUR
 * General montage.
 * A montage of all images is created; channels in rows, images in columns.
 * All single montages obtained in PART THREE are loaded and combined into a single montage.
 * Slide names are added as text labels.
 * The file is saved in the results directory.
 * Since the image does not require great quality, it is saved as a .jpeg, following optional scaling.
 * 
 */



////////////////////////////
///// DATA AND OPTIONS /////
////////////////////////////

// prepare some messages
message_0 = "Welcome to the .oib putter togetherer.\n";
message_1 = "For code and documentation look up \"oib_putter_togetherer.ijm\".\n \n";
message_2 = "We will convert Z stacks to montages of maximum intensity projections.\n";
message_3 = "The images can be pre-processed by applying median blur and/or rolling ball background subtraction.\n";
message_4 = "We will then create a montage of all images so they can be compared easily.\n";
message_5 = "The putter togetherer is compatible with stacks acquired with Olympus CLSM systems saved in .oib and .oif formats.\n";
message_6 = "XYZC stacks are supported. As of 21 September 2018, time-lapse is not.\n";
message_7 = "It is crucial that all your stacks have the same xy pixel dimensions.\n";

message_8 = "Declare the master folder where your files are stored.\n";

message_9 = "Only one image of the DIC Z stack will be used. ";
message_10 = "Which one do you want?\n";
message_11a = "Available choices are: \"Top\", \"High\", \"Middle\", \"Low\", \"Bottom\" \n";
message_11b = "or a number up to the Z-depth of the stacks.";

welcome_address = message_1 + message_2 + message_3 + message_4 + message_5 + message_6 + message_7;
DIC_slice_message = message_9 + message_10 + message_11a + message_11b;

// welcome address
Dialog.create(message_0);
Dialog.addMessage(welcome_address);
Dialog.show();
// open master directory
master = getDirectory(message_8);
// if no relevant files in master or master/input, terminate script
if (!any_oibs(master) && !any_oibs(master + "/input")) exit("Sorry, no files found.");
// main options dialog
Dialog.create("Options");
Dialog.addNumber("How many channels are there in your stacks?", 3);
Dialog.addMessage("Which channel is the transmitted light?");
Dialog.addNumber("(Input 0 if there is none.)", 3);
Dialog.addMessage(DIC_slice_message);
Dialog.addString("Select DIC slice:", "Low");
Dialog.addRadioButtonGroup("add channel labels", newArray("no", "on the left", "on the right"), 1, 3, "no");
Dialog.addCheckbox("channels in colour", true);
Dialog.addCheckbox("process images", true);
Dialog.addCheckbox("labels slides", true);
Dialog.addCheckbox("channel overlays", true);
Dialog.addToSameRow();
Dialog.addNumber("how many?", 1);
Dialog.addCheckbox("panel borders", false);
Dialog.addToSameRow();
Dialog.addNumber("width", 0.01);
Dialog.addToSameRow();
Dialog.addChoice("color", newArray("black", "gray10", "gray25", "gray50", "gray75", "white"), "black");
Dialog.addNumber("scaling factor for general montage", 1);
Dialog.show();
// capture input
channels = Dialog.getNumber();
DIC_channel = Dialog.getNumber();
DIC_slice_choice = Dialog.getString();
labels = Dialog.getRadioButton();
in_color = Dialog.getCheckbox();
processing =  Dialog.getCheckbox();
label_slices =  Dialog.getCheckbox();
overlays = Dialog.getCheckbox();
overlay_number = Dialog.getNumber();
borders = Dialog.getCheckbox();
border_width = Dialog.getNumber() * borders;
border_color = Dialog.getChoice();
scale_factor = Dialog.getNumber();
if (scale_factor <= 0) scale_factor = 1; // in case of stupid input
// advanced options dialog
if (labels != "no" || in_color || processing) {
	Dialog.create("Advanced options");
	if (labels != "no") labels_input();
	if (in_color) color_input();
	if (processing) processing_input();
	Dialog.show();
}
// capture input
channel_labels = labels_output();
colors = color_output();
processors = processing_output();
blur = Array.slice(processors, 0, channels);
subtract = Array.slice(processors, channels, 2*channels);
blur_radii = Array.slice(processors, 2*channels, 3*channels);
for (i = 0; i < blur_radii.length; i++) if (blur_radii[i] <= 0) blur[i] = 0; // in case of stupid input
ball_radii = Array.slice(processors, 3*channels, 4*channels);
for (i = 0; i < ball_radii.length; i++) if (ball_radii[i] <= 0) subtract[i] = 0; // in case of stupid input
// request for overlays overrides request for channel labels
if (labels != "no" && overlays) {
	Dialog.create("Warning!");
	Dialog.addMessage("Channel labels are incompatible with overlays and will be disabled.");
	Dialog.show();
	labels = "no";
}
// overlay options dialog
if (overlays) {
	Dialog.create("Overlay options");
	overlay_input();
	Dialog.show()
}
// capture input
overlay_options = overlay_output();
channels_include = Array.slice(overlay_options, 0, channels * overlay_number);
channels_overcolors = Array.slice(overlay_options, channels * overlay_number, channels * overlay_number * 2);
panel_order = overlay_options[overlay_options.length-1];
panel_order = split(panel_order, "-");

/////////////////////
///// PART ZERO /////
/////////////////////

print("preparing files");
// in case the master directory only contains image files
// create input, temp and results directories and move all oib files to input directory
if (!File.exists(master + "input")) File.makeDirectory(master + "input");
if (!File.exists(master + "temp")) File.makeDirectory(master + "temp");
if (!File.exists(master + "results")) File.makeDirectory(master + "results");
if (!File.exists(master + "rejects")) File.makeDirectory(master + "rejects");
files = getFileList(master);
for (i = 0; i < files.length; i++) {
	if(endsWith(files[i], "\.oib") || endsWith(files[i], "\.oif") || endsWith(files[i], "\.oif\.files/")) {
		File.rename(master + files[i], master + "input/" + files[i]);
	}
}
print("preparations done");

////////////////////
///// PART ONE /////
////////////////////

print("beginning part one: Z projections");
// list files in input directory
files = getFileList(master + "input/");
// isolate names of slides (by stripping file extension)
slides = newArray(files.length);
for(i = 0; i < files.length; i++) slides[i] = substring(files[i], 0, lengthOf(files[i]) - 4);

// for every file: separate channels, create projections and save them in temp directory
for (f = 0; f < files.length; f++) {
	// get and print file name
	file = files[f];
	print("opening file " + file);
	// get slide name
	slide = slides[f];
	// open image
	option_for_bioformats = "open=[" + master + "input/" + file +
							"] autoscale color_mode=Default rois_import=[ROI manager] view=Hyperstack stack_order=XYCZT";
	run("Bio-Formats", option_for_bioformats);
	// rename window to the file name
	rename(slide);
	// get stack dimensions, specifically number of slices and channels
	Stack.getDimensions(width, height, channels, slices, frames);
	// define DIC slice to be used
	DIC_slice = DIC_slicer(slices, DIC_slice_choice);
	if (DIC_slice > slices) exit("The chosen slice is out of range for file " + file + ".");
	
	// split channels
	run("Split Channels");
	// get channel names
	channel_names = getList("image.titles");
	
	/* for all channels (except DIC):
	 *		apply median blur, if requested
	 *		apply rolling ball background subtraction, if requested
	 *		create maximum intensity projection
	 * close original stack
	 */
	for (i = 0; i < channels; i++) {
		selectWindow(channel_names[i]);
		if (i == DIC_channel - 1) {
			// isolate one slice from DIC channel stack
			option_for_substack = " slices=" + DIC_slice;
			run("Make Substack...", option_for_substack);
		} else {
			// apply blur
			if (blur[i]) {
				option_for_blur = "radius=" + blur_radii[i] + " stack";
				run("Median...", option_for_blur);
			}
			// apply backgroud subtraction
			if (subtract[i]) {
				option_for_backgroud = "rolling=" + ball_radii[i] + " stack";
				run("Subtract Background...", option_for_backgroud);
			}
			// create maximum intensity projection
			if (slices > 1) run("Z Project...", "projection=[Max Intensity]");
			}
		selectWindow(channel_names[i]);
		close();
	}

	// get projection names
	projection_names = getList("image.titles");
	// save each image as a tiff file in the temp directory and close it
	for (i = 0; i < channels; i++) {
		selectWindow(projection_names[i]);
		saveAs("Tiff", master + "temp/" + slides[f] + "_C" + i+1 + ".tif");
		close();
	}
}
print("projections done");

////////////////////
///// PART TWO /////
////////////////////

print("beginning part two: Contrast");
// list all files in temp directory
projections = getFileList(master + "temp/");

// for every channel: load files, clip histogram, apply LUT, save files
// unless this is the DIC channel, in which case leave histogram as is
for (i = 0; i < channels; i++) {
	print("adjusting channel " + i+1);
	// open all images of one channel
	channel_pattern =  "_C" + i+1 + ".tif";
	option_for_image_sequence_open = "open=[" + master + "temp/" + projections[i] + "] " + "file=" + channel_pattern + " sort";
	run("Image Sequence...", option_for_image_sequence_open);
	// adjust histograms for non-DIC channels
	if (i != DIC_channel - 1) {
		adjust_histogram(0.05); // function definitions at the end of script
	}
	make_LUT(colors[i]);
	run("RGB Color");
	// save images
	option_for_image_sequence_save = "format=TIFF use save=[" + master + "temp/temp0000.tif]";
	run("Image Sequence... ", option_for_image_sequence_save);
	close("*");
}
print("contrast done");

//////////////////////
///// PART THREE /////
//////////////////////

print("beginning part three: Single Montages");

/* for each slide: load appropriate projections, create montage and save it in the results directory
 * if overlays are requested, make them at this point
 *		strip color from individual channels (convert to 8-bit)
 *		apply appropriate LUTs
 *		merge channels
 * apply channel colors back to individual channels and convert them back to RGB
 */
for (s = 0; s < slides.length; s++) {
	slide = slides[s];
	print("processing slide: " + slide);
	// open all channels of a slice
	option_for_image_sequence_open = "open=[" + master + "temp/" + projections[s] + "] " + "file=" + slide + " sort";
	run("Image Sequence...", option_for_image_sequence_open);
	// move DIC channel to last position
		// but only if no overlays are requested,
		// in which case panel order is set manually and this is up to the user
	if (DIC_channel != 0 && !overlays) {
		option_for_substack = "delete slices=" + DIC_channel;
		run("Make Substack...", option_for_substack);
		rename("Substack");
		run("Concatenate...", "  title=temp image1=temp image2=Substack");		
	}
	// create overlays if requested
	if (overlays) {
		print("making channel overlays");
		// convert stack to grayscale
		run("8-bit");
		// split stack to individual channels
		run("Stack to Images");
		// get window names
		panels = getList("image.titles");
		// overlay creation
		for (o = 0; o < overlay_number; o++) {
			// create name for overlay, based on slide name
			overlay_name = slide + "_O" + o+1;
			// isolate inclusion arrays for channels and colors for current overlay
			channels_include_now = Array.slice(channels_include, o * channels, (o+1) * channels);
			channels_overcolors_now = Array.slice(channels_overcolors, o * channels, (o+1) * channels);
			// set colors for individual channels that will go into overlay
			for (i = 0; i < panels.length; i++) {
				selectWindow(panels[i]);
				make_LUT(channels_overcolors_now[i]);
			}
			// merge
			// merging option is created as array
			option_array = newArray(channels + 1);
			// included channels get pasted into strings, others just get a 0 (must be a string!)
			for (i = 0; i < channels; i++) {
				if (channels_include_now[i]) option_array[i] = "c" + i+1 + "=" + panels[i]; else option_array[i] = "0";
			}
			// additional options are added at the end
			option_array[channels] = "create keep";
			// the array is combined into a single string with custom function
			option_for_merge = unsplit(option_array, " ");			
			// merge; composite is created
			run("Merge Channels...", option_for_merge);
			// convert composite to RGB (new window created), rename it and close the composite
			run("RGB Color");
			rename(overlay_name);
			selectWindow("Composite");
			close();
		}
		// restore original colors to individual channels (listed in panels object) and convert to RGB
		for (p = 0; p < panels.length; p++) {
			selectWindow(panels[p]);
			make_LUT(colors[p]);
			run("RGB Color");
		}
		// wrap images to stack in proper order
		// prepare image order by adding slide name to panel order
		window_order = newArray(panel_order.length);
		for (p = 0; p < panel_order.length; p++) {
			window_order[p] = slide + "_" + panel_order[p];
		}
		// concatenation option is constructed as array
		option_as_array = newArray(window_order.length);
		for (i = 0; i < panel_order.length; i++) {
			option_as_array[i] = "image" + i+1 + "=" + window_order[i];
		}
		// additional options are added at the beginnig
		option_as_array = Array.concat(newArray("  title=slide"), option_as_array);
		// concatenate panels to stack
		option_for_concatenate = unsplit(option_as_array, " ");
		run("Concatenate...", option_for_concatenate);
	}
	print("making montage");
	// make montage
	// determine border width (in pixels) based on input and image dimensions
	if (border_width != 0 && border_width <= 1) border_width = floor(border_width * width);
	// set foreground color for panel borders, based on INPUT
	fg_color(border_color);
	option_for_montage = "columns=" + nSlices + " rows=1 scale=1" + " border=" + border_width + " use";
	run("Make Montage...", option_for_montage);
	// save montage and close all images
	saveAs("Tiff", master + "results/" + "montage_" + slide + ".tif");
	close("*");
}
print("montages done");

/////////////////////
///// PART FOUR /////
/////////////////////

print("beginning part four: General Montage");
// list files in the results folder
montages = getFileList(master + "results/");
if (montages.length == 0 || montages.length == 1) exit("script complete\ngeneral montage omitted");

// if slide labels requested, prepare their format and position
if (label_slices) {
	print("adding slide labels");
	// find longest label
	slide_label_lengths = newArray(slides.length);
	for (i = 0; i < slides.length; i++) slide_label_lengths[i] = lengthOf(slides[i]);
	max_label_length = maximum(slide_label_lengths);
	// set font such that the longest label will take 6/10 of the panel width
	font_size = floor(width * 0.6 / max_label_length);
}

// for each montage:
	// open image
	// rotate it to the right (channel 1 at the top)
	// sign it with the slide name if requested at INPUT
for (m = 0; m < montages.length; m++) {
	open(master + "results/" + montages[m]);
	run("Rotate 90 Degrees Right");
	if (label_slices) {
		// set format
		setJustification("left");
		setColor("white");
		setFont("Monospace", font_size);
		// determine coordinates for the label
		font_height = getValue("font.height"); coordinate = font_height;
		drawString(slides[m], coordinate, coordinate, "black");
	}
}
// wrap images to stack
run("Images to Stack");
print("combining montages");
// set foreground color (for panel borders)
fg_color(border_color);
// make montage, save it and close all images
option_for_montage = "columns=" + montages.length + " rows=1 scale=" + scale_factor + " border=" + floor(border_width * scale_factor) + " use";
run("Make Montage..." , option_for_montage);
// add channel labels to side of general montage
if (labels != "no") {
	print("adding channel labels");
	// first, move DIC channel label to end and rearrange label colors accordingly
	if (labels != "no" && DIC_channel != 0) {
		channel_labels = Array.concat(Array.slice(channel_labels, 0, DIC_channel-1), 
		                              Array.slice(channel_labels, DIC_channel, channel_labels.length), 
		                              channel_labels[DIC_channel-1]);
		colors = Array.concat(Array.slice(colors, 0, DIC_channel-1), 
		                      Array.slice(colors, DIC_channel, colors.length), 
		                      colors[DIC_channel-1]);
	}
	// determine font size
	channel_label_lengths = newArray(channels);
	for (i = 0; i < channels; i++) channel_label_lengths[i] = lengthOf(channel_labels[i]);
	max_label_length = maximum(channel_label_lengths);
	// set font such that the longest label will take 1/2 of the panel width
	font_size = floor(width * 0.5 / max_label_length);
	font_size = floor(font_size * scale_factor);
	// set format
	setFont("Monospace", font_size , "bold");
	// determine coordinates for the labels
	font_height = getValue("font.height"); coordinate = font_height;
	// rotate image
	if (labels == "on the right") {
		run("Rotate 90 Degrees Left");
	} else if (labels == "on the left") {
		label_colors = Array.reverse(colors);
		channel_labels = Array.reverse(channel_labels);
		run("Rotate 90 Degrees Right");
	}
	// add channel labels
	for (i = 0; i < channels; i++) {
		col = make_color(colors[i]); setColor(col);
		drawString(channel_labels[i],
		coordinate * scale_factor + (i * scale_factor * (width + border_width)),
		coordinate * 5/4, "black");
	}
	// rotate image back
	if (labels == "on the right") {
		run("Rotate 90 Degrees Right");
	} else if (labels == "on the left") {
		run("Rotate 90 Degrees Left");
	}
}


// save and close
saveAs("jpg", master + "results/" + "general_montage.jpg");
close("*");
print("general montage done");

print("cleaning up");
copy_all(master + "results", master);
remove(master + "temp");
remove(master + "results");

// reopen final image
open(master + "general_montage.jpg");
// End script.
exit("Script complete.");










////////////////////////////////
///// FUNCTION DEFINITIONS /////
////////////////////////////////

function any_oibs(folder) {
// check in there are any .oib files in a directory
	files = getFileList(folder);
	for (i = 0; i < files.length; i++) {
		if (endsWith(files[i], "\.oib") || endsWith(files[i], "\.oif")) return(true);
	}
	return false;
}


function DIC_slicer(slices, level) {
// determine which slice to select from DIC stack
// used in PART ONE

	if (level == "Top") {
		DIC_slice = 1;
	} else if (level == "High") {
		DIC_slice = floor(slices * 1/3 + 1/3);
	} else if (level == "Middle") {
		DIC_slice = floor(slices * 1/2 + 0.5);
	} else if (level == "Low") {
		DIC_slice = floor(slices * 2/3 + 1/3);
	} else if (level == "Bottom") {
		DIC_slice = slices;
	} else DIC_slice = parseFloat(slices);
	return DIC_slice;
}


function adjust_histogram(saturation) {
// get new histogram borders, based on the entire stack; use montage to display all images at once
// prepare option for montage
	option_for_montage = "columns=" + nSlices + " rows=1 scale=1";
	run("Make Montage...", option_for_montage);
// prepare option for contrast
	option_for_contrast = "saturated=" + saturation * nSlices;
	run("Enhance Contrast", option_for_contrast);
// get histogram borders from montage
	getMinAndMax(min, max);
// close montage
	close("Montage");
// set histogram borders for stack
	setMinAndMax(min, max);
}


function make_LUT(color) {
// convenience function to select a LUT
// used in PART TWO

// by default the LUT will be "Gray"
	reds = newArray(256); greens = newArray(256); blues = newArray(256);
	for (i=0; i<256; i++) { reds[i] = i; greens[i] = i; blues[i] = i; }
// custom colours
	if (color == "Hoechst" || color == "hoechst" || color == "DNA" || color == "#3faaff") {
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
// standard colors
	else if (color == "Red" || color == "red" || color == "#ff00") {
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
	setLut(reds, greens, blues);
}


function make_color(color){
// make hex codes of colors named by string
	// built-in colors
	if (color == "red") return "#" + toHex(255) + "00" + "00";
	if (color == "green") return "#" + "00" + toHex(255) + "00";
	if (color == "blue") return "#" + "00" + "00" + toHex(255);
	if (color == "cyan") return "#" + "00" + toHex(255) + toHex(255);
	if (color == "magenta") return "#" + toHex(255) + "00" + toHex(255);
	if (color == "yellow") return "#" + toHex(255) + toHex(255) + "00";
	if (color == "gray") return "#" + toHex(255) + toHex(255) + toHex(255);
	if (color == "Hi-Lo") return "#" + toHex(255) + toHex(255) + toHex(255);
	// custom colors
	if (color == "redish") return "#" + toHex(255) + toHex(255 * 1/5) + toHex(255 * 1/5);
	if (color == "greenish") return "#" + "00" + toHex(255) + toHex(255 * 1/3);
	if (color == "blueish") return "#" + toHex(255 * 1/4) + toHex(255 * 2/3) + toHex(255);
	if (color == "yellowish") return "#" + toHex(255) + toHex(255) + toHex(255 * 1/4);	
}


/// SET OF UI FUNCTIONS FOR USER DEFINED PARAMETERS
function labels_input() {
// give channel labels
	label_defaults = newArray(channels); for (i = 0; i < channels; i++) label_defaults[i] = "channel " + i+1;
	Dialog.addMessage("Channel labels");
	for (i = 0; i < channels; i++) {
		if (i == DIC_channel-1) {
			Dialog.addString("label", "");
		} else {
		Dialog.addString("label", label_defaults[i]);
		}
	}
}
function labels_output() {
// read channel labels
	channel_labels = newArray(channels); for (i = 0; i < channels; i++) channel_labels[i] = "";
	if (labels != "no") for (i = 0; i < channels; i++) channel_labels[i] = Dialog.getString();
	return channel_labels;
}
function color_input() {
// select colours for channels and their labels
	// list of available colors for channels and their labels
	available_colors = newArray("gray", "redish", "greenish", "blueish", "yellowish", 
								"red", "green", "blue", "cyan", "yellow", "magenta", "Hi-Lo");
	// default colors
	color_defaults = newArray("blueish", "yellowish", "greenish", "redish", "blue", "green", "red", "yellow");
	Dialog.addMessage("Colurs");
	for (i = 0; i < channels; i++) {
		if (i == DIC_channel-1) {
			Dialog.addChoice("colour for channel " + i+1, available_colors, "gray");
		} else {
			Dialog.addChoice("colour for channel " + i+1, available_colors, color_defaults[i]);
		}
	}
}
function color_output() {
// read input for channel colors
	colors = newArray(channels); for (i = 0; i < channels; i++) colors[i] = "gray";
	if (in_color) for (i = 0; i < channels; i++) colors[i] = Dialog.getChoice();
	return colors;
}
function processing_input() {
// determine image processing
	Dialog.addMessage("Image processing");
	for (i = 0; i < channels; i++) {
		if (i == DIC_channel-1) {
			Dialog.addCheckbox("Median filter for channel " + i+1, false);
		} else {
			Dialog.addCheckbox("Median filter for channel " + i+1, true);
		}
		Dialog.addToSameRow();
		Dialog.addNumber("radius", 1);
		if (i == DIC_channel-1) {
			Dialog.addCheckbox("Background subtraction for channel " + i+1, false);
		} else {
			Dialog.addCheckbox("Background subtraction for channel " + i+1, true);
		}
		Dialog.addToSameRow();
		Dialog.addNumber("rolling ball radius", 80);
	}
}
function processing_output() {
// read input for processing
	// create default values
	blur = newArray(channels); for (i = 0; i < channels; i++) blur[i] = false;
	subtract = newArray(channels); for (i = 0; i < channels; i++) subtract[i] = false;
	blur_radii = newArray(channels); for (i = 0; i < channels; i++) blur_radii[i] = 0;
	ball_radii = newArray(channels); for (i = 0; i < channels; i++) ball_radii[i] = 0;
	// if processing desired, read input
	if (processing) for (i = 0; i < channels; i ++) {
		blur[i] = Dialog.getCheckbox();
		subtract[i] = Dialog.getCheckbox();
		blur_radii[i] = Dialog.getNumber();
		ball_radii[i] = Dialog.getNumber();
	}
	bool = Array.concat(blur, subtract);
	numb = Array.concat(blur_radii, ball_radii);
	processing_parameters = Array.concat(bool, numb);
	return processing_parameters;
}
function overlay_input() {
	available_colors = newArray("gray", "redish", "greenish", "blueish", "yellowish", "red", "green", "blue", "cyan", "yellow", "magenta");
	Dialog.addMessage("Overlays:");
	for (i = 0; i < overlay_number; i++) {
		Dialog.addMessage("overlay " + i+1);
		for (c = 0; c < channels; c++) {
			Dialog.addCheckbox("channel " + c+1 + ": " + channel_labels[c], false);
			if (!in_color) {
				Dialog.addToSameRow();
				Dialog.addChoice("color:", available_colors, colors[c]);
			}
		}
	}
	// construct default panel order by interleaving channels and overlays
	ch = newArray(channels); for (i = 0; i < channels; i++) ch[i] = "c" + i+1;
	ov = newArray(overlay_number); for (i = 0; i < overlay_number; i++) ov[i] = "o" + i+1;
	order_default = unsplit(interleave(ch,ov), "-");
	Dialog.addString("panel order:", order_default);
}
function overlay_output() {
	channels_include = newArray(overlay_number * channels);
	channels_overlay_colors = newArray(overlay_number * channels);
	ch = newArray(channels); for (i = 0; i < channels; i++) ch[i] = "c" + i+1;
	panel_order = unsplit(ch, "-");
	if (overlays) {
		for (o = 0; o < overlay_number; o++) {
			for (i = 0; i < channels; i++) {
				channels_include[i + o * channels] = Dialog.getCheckbox();
				if (in_color) {
					channels_overlay_colors[i + o * channels] = colors[i];
				} else {
					channels_overlay_colors[i + o * channels] = Dialog.getChoice();
				}
			}
		}
		panel_order = toUpperCase(Dialog.getString());
	}
// check for potential errors: less than two channels to overlay or all gray panels to overlay
	if (overlays) {
		for (o = 0; o < overlay_number; o++) {
			channels_include_part = Array.slice(channels_include, o * channels, (o+1) * channels);
			if (sum_array(channels_include_part) < 2) exit("Input Error:\noverlays require at least two channels");

			channels_overlay_colors_part = Array.slice(channels_overlay_colors, o * channels, (o+1) * channels);
			is_gray = newArray(channels);
			for (i = 0; i < is_gray.length; i++) if (channels_overlay_colors_part[i] == "gray") is_gray[i] = true; else is_gray[i] = false;
			if (all(is_gray)) exit("Input Error:\noverlays must not consist only of gray panels");
		}		
	}
// end checks
	overlay_options = Array.concat(channels_include, channels_overlay_colors, panel_order);
	return overlay_options;
}
//// END UI FUNCTIONS


function interleave(array1, array2) {
// interleave two arrays
	if (array1.length <= array2.length) {shorter = array1; longer = array2;} else {longer = array1; shorter = array2;}
	A = newArray();
	for (i = 0; i < shorter.length; i++) A = Array.concat(A, array1[i], array2[i]);
	leftovers = Array.slice(longer, shorter.length ,longer.length);
	Al = Array.concat(A, leftovers);
	return Al;
}


function unsplit(arr, sep) {
//concatenate elements of array with separator
	x = arr;
	y = x[0];
	for (i = 1; i < x.length; i++) y = y + sep + x[i];
	return y;
}


function remove(file) {
// delete a file or a non-empty directory (recursively)

	if (File.isDirectory(file)) {
		contents = getFileList(file);
		if (contents.length != 0) for (i = 0; i < contents.length; i++) {
			if (File.isDirectory(file + File.separator + contents[i])) remove(file + File.separator + contents[i]);
			File.delete(file + File.separator + contents[i]);
		}		
	}
	File.delete(file);
}


function copy_all(path1, path2) {
// copy file or contents of directory (recursively)
// path1 may be a file or a directory
// path2 must be a file or an existing directory, respectively

	if (!File.exists(path1)) exit("\"path1\" does not exist");
	if (File.isDirectory(path2) && !File.isDirectory(path1)) exit("\"path2\" must be file path");
	if (File.isDirectory(path2) && !File.exists(path2)) exit("\"path2\" must be an existing directory");

	if (File.isDirectory(path1)) {
		File.makeDirectory(path2);
		contents = getFileList(path1);
		for (i = 0; i < contents.length; i++) copy_all(path1 + File.separator + contents[i], path2 + File.separator + contents[i]);
	} else {
		File.copy(path1, path2);
	}
}


function fg_color(color) {
// set foreground color according to choice in main options window
	if (color == "black") setForegroundColor(0, 0, 0);
	if (color == "gray10") setForegroundColor(25, 25, 25);
	if (color == "gray25") setForegroundColor(64, 64, 64);
	if (color == "gray50") setForegroundColor(127, 127, 127);
	if (color == "gray75") setForegroundColor(192, 192, 192);
	if (color == "white") setForegroundColor(255, 255, 255);
}


function maximum(arr) {
// get maximum value of array
// wrapper for Array method
	Array.getStatistics(arr, min, max, mean, stdDev);
	return max;
}


function sum_array(arr) {
// return sum of all elements of the array
	res = 0;
	for (i = 0; i < arr.length ; i++) res = res + arr[i];
	return res;
}


function all(arr) {
// check whether all elements of array are true
	for (i = 0; i < arr.length; i ++) if (!arr[i]) return(false);
	return true;
}

