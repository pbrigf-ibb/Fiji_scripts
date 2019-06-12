/* by Aleksander Chlebowski
 * Warsaw, 25 January 2019
 */

// update	30 January 2019		added options interface
//								added options for plate montage
// update	31 January 2019		moved warnings from log window to pop-up dialogs
// update	1 February 2019		overhaul of the method:
//								rather than files being segregated into separate plate/channel files
//									(this is done by parts one and two)
//									all files have their plate names added to their names and are stored together
//									the script begins with listing all images and extracting plate and channel information from their names
// update	4 February 2019		overhaul partially rolled back 
//									listing large numbers of files and finding uniques among such set proved very time-consuming
//									files are still kept in separate plate folders but not as separate channels
//									the data folder is kept for the time being, pending some benchmarking of PART ONE
//									Unix based PART TWO is now obsolete; documentation amended
// update	6 Ferbuary 2019		check for missing images in plate-channel sets
//									channel construction is skipped if number of tiles doesn't match the expected one
// update	9 May 2019			bug fixed: median filter now working
//								minor corrections to documentation

/* This is part two of a three part procedure that aims
 * to combine a set of images from a high-throughput microscopy screen 
 * into a few images that are aeasily viewable to facilitate manual inspection.
 * 
 * PART ONE is run in R.
 * It removes excess files, modifies image file names so that they properly fit into a well montage,
 * and incorporates the plate name into the file names.
 * 
 * PART TWO is done in ImageJ.
 * It detects plates and channels, sequentially opens consecutive plate-channel combinations,
 * modifies the images for consistent viewing and arranges them into large plate-like images.
 * 	1. Images are processed: a slight blur is applied and background is subtracted.
 * 	2. A common display mode is set for the entire plate.
 * 	3. Images from each well are arranged as tiles in a larger image.
 * 	4. A text label is added to each well image that contains the plate name and well position on that plate.
 * 	5. Well montages are arranged into a plate montage, in which wells are separated by a border.
 * 	6. The resulting file is properly named and saved.
 * 
 * PART THREE is also run in ImageJ, but from a separate script.
 * It produces multi-color composites of the plate montages.
 */
 
/* DYNAMIC features:	
 *  
 * master directory: this is the top directory where all the work takes place 
 * 	the script will refer to subdirectories of the master: collected_images, plate views and plate views in color
 * well montage parameters (grid dimensions and image scaling)
 * placement and size of the text label
 * scaling of the plate montage
 * plate montage parameters (grid dimensions and image scaling)
 * image processing parameters (filter type, filter diameter, rolling ball radius)
 * 
 * STATIC features:
 * 	currently none
 * 
 * DEVELOPMENT:
 *  add more processing options (in dreams)
 * 	
 */

 


// INPUT BASIC OPTIONS
master = getDirectory("Declare master directory:");
Dialog.create("Options");
Dialog.addNumber("number of tiles:", 6);
Dialog.addMessage("well montage grid and scaling:");
Dialog.addNumber("rows", 3); Dialog.addToSameRow();
Dialog.addNumber("columns", 2); Dialog.addToSameRow();
Dialog.addNumber("scaling", 0.25);
Dialog.addMessage("text label coordinates and size\n(defaults for well scaling of 0.25)");
Dialog.addNumber("X", 8); Dialog.addToSameRow();
Dialog.addNumber("Y", 20); Dialog.addToSameRow();
Dialog.addNumber("font size", 20);
Dialog.addMessage("plate montage grid and scaling:");
Dialog.addNumber("rows", 16); Dialog.addToSameRow();
Dialog.addNumber("columns", 24); Dialog.addToSameRow();
Dialog.addNumber("scaling", 0.5); Dialog.addToSameRow();
Dialog.addNumber("border width", 2);
Dialog.addCheckbox("image processing options", true);
Dialog.show();

target_directory = master + "plate views/";
fovs = Dialog.getNumber();
rows = Dialog.getNumber();
columns = Dialog.getNumber();
well_scaling = Dialog.getNumber();
string_coord_x = Dialog.getNumber();
string_coord_y = Dialog.getNumber();
font_size = Dialog.getNumber();
plate_rows = Dialog.getNumber();
plate_columns = Dialog.getNumber();
plate_scaling = Dialog.getNumber();
plate_border = Dialog.getNumber();
advanced = Dialog.getCheckbox();
// in case of stupid:
if (fovs <= 0 || columns <= 0 || rows <= 0 || well_scaling <= 0 || 
	string_coord_x <= 0 || string_coord_y <= 0 || font_size <= 0 || 
	plate_rows <= 0 || plate_columns <= 0 || plate_scaling <= 0) exit("ERROR:\ninvalid parameter\nonly positive values allowed");
if (plate_border < 0) {
	plate_border = 0;
	Dialog.create("WARNING"); Dialog.addMessage("width of border in plate montage was set to zero"); Dialog.show();
}
if (well_scaling > 1) well_scaling = 1;
if (plate_scaling > 1) plate_scaling = 1;
if (columns * rows != fovs) exit("ERROR:\ndimensions of well montage grid do not match the fields of view");
if (font_size > string_coord_y) {
	string_coord_y = font_size;
	Dialog.create("WARNING"); Dialog.addMessage("Y coordinate of text label was adjusted to font size"); Dialog.show();
}
// stupidity covered
// BASIC INPUT COMPLETE
// MORE MAY COME AFTER DETECTING CHANNELS AND PLATES

// create target directory for storing the plate views
if (!File.exists(target_directory)) File.makeDirectory(target_directory);

// get file list, select only directories that match the plate name regular expression
all_files = getFileList(master);
plates = newArray(0);
for (f = 0; f < all_files.length; f++) {
	if (matches(all_files[f], "[0-9]{3}[A-Z,0-9]\\.[0-9]{8}\\.S[0-9]{2}\\.[A-Z][0-9]{2}/")) plates = Array.concat(plates, all_files[f]);
}

print("detecting channels");
// isolate channel names from file names
all_image_files = getFileList(master + plates[0] + "data/");
all_channels = newArray(all_image_files.length);
for (f = 0; f < all_image_files.length; f++) {
	image_name_split = split(all_image_files[f], "--");
	all_channels[f] = image_name_split[image_name_split.length-1];
}
// get uniques
channels = unique(all_channels);

// INPUT ADVANCED OPTIONS (if requested)
if (advanced) {
	advanced_options_input();
}
advanced_options = advanced_options_returned();
blur_mode = Array.slice(advanced_options, 0, channels.length);
blur_radius = Array.slice(advanced_options, channels.length, 2 * channels.length);
background_radius = Array.slice(advanced_options, 2 * channels.length, 3 * channels.length);
// INPUT COMPLETE

// establish how many images there should be in total, per plate per channel
full_complement = fovs * plate_rows * plate_columns;
		
for (p = 0; p < plates.length; p++) {
	platedir = plates[p];
	plate = substring(platedir, 0, lengthOf(platedir)-1);
	print("begin plate " + plate);
	for (c = 0; c < channels.length; c++) {
		channel = channels[c];
		print("  begin channel " + channel);
		
		final_file = target_directory + plate + "_whole_plate_view_" + channel + ".tif";
		if (File.exists(final_file)) {print("   this one is already done"); continue;}
		// open all files for this plate and this channel
		// paranetheses denote regular expression
		run("Image Sequence...", "open=[" + master + plate + "/data/] file=(.*" + channel + ") sort");
		rename(channel);
		run("Out [-]");	run("Out [-]");	run("Out [-]");

		// check if full complement of image files is present
		if (nSlices != full_complement) {
			print("   WARNING: some images for this channel are missing!");
			print("   channel omitted");
			continue;
			}

		// smooth a little and subtract background
		if (blur_mode[c] != "none") run(blur_mode[c], blur_radius[c] + " stack");
		if (background_radius[c] != 0) run("Subtract Background...", "rolling=" + background_radius[c] + " stack");

		// get brightness statistics of the entire stack
		Stack.getStatistics(voxelCount, mean, min, max, stdDev);
		// set new min and max values
		low = floor(mean - stdDev); high = floor(mean + 10* stdDev); setMinAndMax(low, high);
		run("8-bit");
		// set font and intensity of plate name (applied later to montage borders as well) and string background
		setFont("Monospace", font_size);
		setColor(200, 200, 200);

		// get number of wells
		nwells = nSlices / fovs;

		// the following loop removes one well (fovs number of images) from the stack, montages them and renames the montage
		for (well = 1; well < nwells; well++) {
			selectWindow(channel);
			run("Make Substack...", "delete slices=1-" + fovs);
			well_montage("Substack (1-"+ fovs + ")");
		}

		// the last well is montaged from the original stack (substacking impossible at this point)
		well_montage(channel);
		
		// wrap all wells into a single stack
		run("Images to Stack");

		// make whole plate montage and close stack
		option_for_montage = "columns=" + plate_columns + " rows=" + plate_rows + " scale=" + plate_scaling + " border=" + plate_border + " use";
		run("Make Montage...", option_for_montage);
		selectWindow("Stack"); close();

		// save and close montage
		save(final_file);
		selectWindow("Montage"); close();
		print("   channel done");
	}
	print(" plate done");
}
print("that was the last one");
exit("finished");



// FUNCTION DEFINITIONS
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

function sum(array) {
// return sum of all elements of array
	s = 0;
	for (i = 0; i < array.length; i++) s = s + array[i];
	return s;
}

function any(array) {
// check whether any element of a array is true
	for (i = 0; i < array.length; i ++) if (array[i]) return(true);
	return false;
}

function well_montage(window_title) {
// put images of a single well (with potential dummy files) into a montage
// takes existing variables set at the beginning of script:
//	variables	columns, rows						determine montage grid
//	variable	well_scaling						determines image scaling during montage construction
//	variables	string_coord_x, string_coord_y		position of plate and well name in the image
// and variables created during the run:
//	variable	platename							name of current plate (string)
//	variables	nwells, well						used to display well identifier
// also calls another proprietary function
//	function	translate							translates well number into a "A01" type identifier, if possible
// ARGUMENTS
//	argument	window_title						title of window to act upon
	option_for_montage = "columns=" + columns + " rows=" + rows + " scale=" + well_scaling;
	selectWindow(window_title);
	run("Make Montage...", option_for_montage);
	selectWindow(window_title); close();
	selectWindow("Montage");
	wellname = translate(nwells, well);
	rename("Montage-" + wellname);
	drawString(plate + " well " + wellname, string_coord_x, string_coord_y, "black");
}

function translate(nwells, well) {
// translate well number into a "A01" type identifier, if possible
// currently available dictionaries support the following formats:
//		384 wells	full plate
//		384 wells	rows B through O; rows A and P are omitted
//		24 wells	full plate
//		6 wells		full plate
//		1 well		the only well
// takes existing variables created during the run:
//	variables	nwells, well						used to display well identifier
	if (nwells == 384 || nwells == 336) {
		if (nwells == 384) well = well; else if (nwells == 336) well = well + 24;
		if (well == 1) return "A01";
		if (well == 2) return "A02";
		if (well == 3) return "A03";
		if (well == 4) return "A04";
		if (well == 5) return "A05";
		if (well == 6) return "A06";
		if (well == 7) return "A07";
		if (well == 8) return "A08";
		if (well == 9) return "A09";
		if (well == 10) return "A10";
		if (well == 11) return "A11";
		if (well == 12) return "A12";
		if (well == 13) return "A13";
		if (well == 14) return "A14";
		if (well == 15) return "A15";
		if (well == 16) return "A16";
		if (well == 17) return "A17";
		if (well == 18) return "A18";
		if (well == 19) return "A19";
		if (well == 20) return "A20";
		if (well == 21) return "A21";
		if (well == 22) return "A22";
		if (well == 23) return "A23";
		if (well == 24) return "A24";
		if (well == 25) return "B01";
		if (well == 26) return "B02";
		if (well == 27) return "B03";
		if (well == 28) return "B04";
		if (well == 29) return "B05";
		if (well == 30) return "B06";
		if (well == 31) return "B07";
		if (well == 32) return "B08";
		if (well == 33) return "B09";
		if (well == 34) return "B10";
		if (well == 35) return "B11";
		if (well == 36) return "B12";
		if (well == 37) return "B13";
		if (well == 38) return "B14";
		if (well == 39) return "B15";
		if (well == 40) return "B16";
		if (well == 41) return "B17";
		if (well == 42) return "B18";
		if (well == 43) return "B19";
		if (well == 44) return "B20";
		if (well == 45) return "B21";
		if (well == 46) return "B22";
		if (well == 47) return "B23";
		if (well == 48) return "B24";
		if (well == 49) return "C01";
		if (well == 50) return "C02";
		if (well == 51) return "C03";
		if (well == 52) return "C04";
		if (well == 53) return "C05";
		if (well == 54) return "C06";
		if (well == 55) return "C07";
		if (well == 56) return "C08";
		if (well == 57) return "C09";
		if (well == 58) return "C10";
		if (well == 59) return "C11";
		if (well == 60) return "C12";
		if (well == 61) return "C13";
		if (well == 62) return "C14";
		if (well == 63) return "C15";
		if (well == 64) return "C16";
		if (well == 65) return "C17";
		if (well == 66) return "C18";
		if (well == 67) return "C19";
		if (well == 68) return "C20";
		if (well == 69) return "C21";
		if (well == 70) return "C22";
		if (well == 71) return "C23";
		if (well == 72) return "C24";
		if (well == 73) return "D01";
		if (well == 74) return "D02";
		if (well == 75) return "D03";
		if (well == 76) return "D04";
		if (well == 77) return "D05";
		if (well == 78) return "D06";
		if (well == 79) return "D07";
		if (well == 80) return "D08";
		if (well == 81) return "D09";
		if (well == 82) return "D10";
		if (well == 83) return "D11";
		if (well == 84) return "D12";
		if (well == 85) return "D13";
		if (well == 86) return "D14";
		if (well == 87) return "D15";
		if (well == 88) return "D16";
		if (well == 89) return "D17";
		if (well == 90) return "D18";
		if (well == 91) return "D19";
		if (well == 92) return "D20";
		if (well == 93) return "D21";
		if (well == 94) return "D22";
		if (well == 95) return "D23";
		if (well == 96) return "D24";
		if (well == 97) return "E01";
		if (well == 98) return "E02";
		if (well == 99) return "E03";
		if (well == 100) return "E04";
		if (well == 101) return "E05";
		if (well == 102) return "E06";
		if (well == 103) return "E07";
		if (well == 104) return "E08";
		if (well == 105) return "E09";
		if (well == 106) return "E10";
		if (well == 107) return "E11";
		if (well == 108) return "E12";
		if (well == 109) return "E13";
		if (well == 110) return "E14";
		if (well == 111) return "E15";
		if (well == 112) return "E16";
		if (well == 113) return "E17";
		if (well == 114) return "E18";
		if (well == 115) return "E19";
		if (well == 116) return "E20";
		if (well == 117) return "E21";
		if (well == 118) return "E22";
		if (well == 119) return "E23";
		if (well == 120) return "E24";
		if (well == 121) return "F01";
		if (well == 122) return "F02";
		if (well == 123) return "F03";
		if (well == 124) return "F04";
		if (well == 125) return "F05";
		if (well == 126) return "F06";
		if (well == 127) return "F07";
		if (well == 128) return "F08";
		if (well == 129) return "F09";
		if (well == 130) return "F10";
		if (well == 131) return "F11";
		if (well == 132) return "F12";
		if (well == 133) return "F13";
		if (well == 134) return "F14";
		if (well == 135) return "F15";
		if (well == 136) return "F16";
		if (well == 137) return "F17";
		if (well == 138) return "F18";
		if (well == 139) return "F19";
		if (well == 140) return "F20";
		if (well == 141) return "F21";
		if (well == 142) return "F22";
		if (well == 143) return "F23";
		if (well == 144) return "F24";
		if (well == 145) return "G01";
		if (well == 146) return "G02";
		if (well == 147) return "G03";
		if (well == 148) return "G04";
		if (well == 149) return "G05";
		if (well == 150) return "G06";
		if (well == 151) return "G07";
		if (well == 152) return "G08";
		if (well == 153) return "G09";
		if (well == 154) return "G10";
		if (well == 155) return "G11";
		if (well == 156) return "G12";
		if (well == 157) return "G13";
		if (well == 158) return "G14";
		if (well == 159) return "G15";
		if (well == 160) return "G16";
		if (well == 161) return "G17";
		if (well == 162) return "G18";
		if (well == 163) return "G19";
		if (well == 164) return "G20";
		if (well == 165) return "G21";
		if (well == 166) return "G22";
		if (well == 167) return "G23";
		if (well == 168) return "G24";
		if (well == 169) return "H01";
		if (well == 170) return "H02";
		if (well == 171) return "H03";
		if (well == 172) return "H04";
		if (well == 173) return "H05";
		if (well == 174) return "H06";
		if (well == 175) return "H07";
		if (well == 176) return "H08";
		if (well == 177) return "H09";
		if (well == 178) return "H10";
		if (well == 179) return "H11";
		if (well == 180) return "H12";
		if (well == 181) return "H13";
		if (well == 182) return "H14";
		if (well == 183) return "H15";
		if (well == 184) return "H16";
		if (well == 185) return "H17";
		if (well == 186) return "H18";
		if (well == 187) return "H19";
		if (well == 188) return "H20";
		if (well == 189) return "H21";
		if (well == 190) return "H22";
		if (well == 191) return "H23";
		if (well == 192) return "H24";
		if (well == 193) return "I01";
		if (well == 194) return "I02";
		if (well == 195) return "I03";
		if (well == 196) return "I04";
		if (well == 197) return "I05";
		if (well == 198) return "I06";
		if (well == 199) return "I07";
		if (well == 200) return "I08";
		if (well == 201) return "I09";
		if (well == 202) return "I10";
		if (well == 203) return "I11";
		if (well == 204) return "I12";
		if (well == 205) return "I13";
		if (well == 206) return "I14";
		if (well == 207) return "I15";
		if (well == 208) return "I16";
		if (well == 209) return "I17";
		if (well == 210) return "I18";
		if (well == 211) return "I19";
		if (well == 212) return "I20";
		if (well == 213) return "I21";
		if (well == 214) return "I22";
		if (well == 215) return "I23";
		if (well == 216) return "I24";
		if (well == 217) return "J01";
		if (well == 218) return "J02";
		if (well == 219) return "J03";
		if (well == 220) return "J04";
		if (well == 221) return "J05";
		if (well == 222) return "J06";
		if (well == 223) return "J07";
		if (well == 224) return "J08";
		if (well == 225) return "J09";
		if (well == 226) return "J10";
		if (well == 227) return "J11";
		if (well == 228) return "J12";
		if (well == 229) return "J13";
		if (well == 230) return "J14";
		if (well == 231) return "J15";
		if (well == 232) return "J16";
		if (well == 233) return "J17";
		if (well == 234) return "J18";
		if (well == 235) return "J19";
		if (well == 236) return "J20";
		if (well == 237) return "J21";
		if (well == 238) return "J22";
		if (well == 239) return "J23";
		if (well == 240) return "J24";
		if (well == 241) return "K01";
		if (well == 242) return "K02";
		if (well == 243) return "K03";
		if (well == 244) return "K04";
		if (well == 245) return "K05";
		if (well == 246) return "K06";
		if (well == 247) return "K07";
		if (well == 248) return "K08";
		if (well == 249) return "K09";
		if (well == 250) return "K10";
		if (well == 251) return "K11";
		if (well == 252) return "K12";
		if (well == 253) return "K13";
		if (well == 254) return "K14";
		if (well == 255) return "K15";
		if (well == 256) return "K16";
		if (well == 257) return "K17";
		if (well == 258) return "K18";
		if (well == 259) return "K19";
		if (well == 260) return "K20";
		if (well == 261) return "K21";
		if (well == 262) return "K22";
		if (well == 263) return "K23";
		if (well == 264) return "K24";
		if (well == 265) return "L01";
		if (well == 266) return "L02";
		if (well == 267) return "L03";
		if (well == 268) return "L04";
		if (well == 269) return "L05";
		if (well == 270) return "L06";
		if (well == 271) return "L07";
		if (well == 272) return "L08";
		if (well == 273) return "L09";
		if (well == 274) return "L10";
		if (well == 275) return "L11";
		if (well == 276) return "L12";
		if (well == 277) return "L13";
		if (well == 278) return "L14";
		if (well == 279) return "L15";
		if (well == 280) return "L16";
		if (well == 281) return "L17";
		if (well == 282) return "L18";
		if (well == 283) return "L19";
		if (well == 284) return "L20";
		if (well == 285) return "L21";
		if (well == 286) return "L22";
		if (well == 287) return "L23";
		if (well == 288) return "L24";
		if (well == 289) return "M01";
		if (well == 290) return "M02";
		if (well == 291) return "M03";
		if (well == 292) return "M04";
		if (well == 293) return "M05";
		if (well == 294) return "M06";
		if (well == 295) return "M07";
		if (well == 296) return "M08";
		if (well == 297) return "M09";
		if (well == 298) return "M10";
		if (well == 299) return "M11";
		if (well == 300) return "M12";
		if (well == 301) return "M13";
		if (well == 302) return "M14";
		if (well == 303) return "M15";
		if (well == 304) return "M16";
		if (well == 305) return "M17";
		if (well == 306) return "M18";
		if (well == 307) return "M19";
		if (well == 308) return "M20";
		if (well == 309) return "M21";
		if (well == 310) return "M22";
		if (well == 311) return "M23";
		if (well == 312) return "M24";
		if (well == 313) return "N01";
		if (well == 314) return "N02";
		if (well == 315) return "N03";
		if (well == 316) return "N04";
		if (well == 317) return "N05";
		if (well == 318) return "N06";
		if (well == 319) return "N07";
		if (well == 320) return "N08";
		if (well == 321) return "N09";
		if (well == 322) return "N10";
		if (well == 323) return "N11";
		if (well == 324) return "N12";
		if (well == 325) return "N13";
		if (well == 326) return "N14";
		if (well == 327) return "N15";
		if (well == 328) return "N16";
		if (well == 329) return "N17";
		if (well == 330) return "N18";
		if (well == 331) return "N19";
		if (well == 332) return "N20";
		if (well == 333) return "N21";
		if (well == 334) return "N22";
		if (well == 335) return "N23";
		if (well == 336) return "N24";
		if (well == 337) return "O01";
		if (well == 338) return "O02";
		if (well == 339) return "O03";
		if (well == 340) return "O04";
		if (well == 341) return "O05";
		if (well == 342) return "O06";
		if (well == 343) return "O07";
		if (well == 344) return "O08";
		if (well == 345) return "O09";
		if (well == 346) return "O10";
		if (well == 347) return "O11";
		if (well == 348) return "O12";
		if (well == 349) return "O13";
		if (well == 350) return "O14";
		if (well == 351) return "O15";
		if (well == 352) return "O16";
		if (well == 353) return "O17";
		if (well == 354) return "O18";
		if (well == 355) return "O19";
		if (well == 356) return "O20";
		if (well == 357) return "O21";
		if (well == 358) return "O22";
		if (well == 359) return "O23";
		if (well == 360) return "O24";
		if (well == 361) return "P01";
		if (well == 362) return "P02";
		if (well == 363) return "P03";
		if (well == 364) return "P04";
		if (well == 365) return "P05";
		if (well == 366) return "P06";
		if (well == 367) return "P07";
		if (well == 368) return "P08";
		if (well == 369) return "P09";
		if (well == 370) return "P10";
		if (well == 371) return "P11";
		if (well == 372) return "P12";
		if (well == 373) return "P13";
		if (well == 374) return "P14";
		if (well == 375) return "P15";
		if (well == 376) return "P16";
		if (well == 377) return "P17";
		if (well == 378) return "P18";
		if (well == 379) return "P19";
		if (well == 380) return "P20";
		if (well == 381) return "P21";
		if (well == 382) return "P22";
		if (well == 383) return "P23";
		if (well == 384) return "P24";	
	} else if (nwells == 6) {
		if (well == 1) return "A1";
		if (well == 2) return "A2";
		if (well == 3) return "A3";
		if (well == 4) return "B1";
		if (well == 5) return "B2";
		if (well == 6) return "B3";
	} else if (nwells == 24) {
		if (well == 1) return "A1";
		if (well == 2) return "A2";
		if (well == 3) return "A3";
		if (well == 4) return "A4";
		if (well == 5) return "A5";
		if (well == 6) return "A6";
		if (well == 7) return "B1";
		if (well == 8) return "B2";
		if (well == 9) return "B3";
		if (well == 10) return "B4";
		if (well == 11) return "B5";
		if (well == 12) return "B6";
		if (well == 13) return "C1";
		if (well == 14) return "C2";
		if (well == 15) return "C3";
		if (well == 16) return "C4";
		if (well == 17) return "C5";
		if (well == 18) return "C6";
		if (well == 19) return "D1";
		if (well == 20) return "D2";
		if (well == 21) return "D3";
		if (well == 22) return "D4";
		if (well == 23) return "D5";
		if (well == 24) return "D6";
	} else if (nwells == 1) {
		return "well 1";
	} else {
		print("WARNING: unknown well-position key");
		return well;
	}
}

function advanced_options_input() {
	Dialog.create("Advanced options");
	for (c = 0; c < channels.length; c++) {
		if (c == 0)	Dialog.addMessage("select blur mode, blur radius and background subtraction radius");
		Dialog.addChoice("channel " + channels[c], newArray("none", "Gaussian Blur", "Median"), "Gaussian Blur");
		Dialog.addToSameRow();
		Dialog.addNumber("", 1.5);
		Dialog.addToSameRow();
		if (channels[c] == "DCP1A" || channels[c] == "J2" || channels[c] == "BrU") defrad = 2; else defrad = 85;
		Dialog.addNumber("", defrad);
	}
	Dialog.show();
}

function advanced_options_returned() {
	blur_mode = newArray(channels.length); for (i = 0; i < channels.length; i++) blur_mode[i] = "none";
	blur_radius = newArray(channels.length); for (i = 0; i < channels.length; i++) blur_radius[i] = 0;
	background_radius = newArray(channels.length); for (i = 0; i < channels.length; i++) background_radius[i] = 0;
	if (advanced) {
		for (c = 0; c < channels.length; c++) {
			blur_mode[c] = Dialog.getChoice();
			blur_radius[c] = Dialog.getNumber();
			background_radius[c] = Dialog.getNumber();
		}
		for (c = 0; c < channels.length; c++) {
			if (blur_mode[c] != "none") blur_mode[c] = blur_mode[c] + "...";
			if (blur_mode[c] == "Gaussian Blur...") prefix = "sigma="; else prefix = "radius=";
			blur_radius[c] = prefix + blur_radius[c];
		}	
	}
	advanced_options = Array.concat(blur_mode, blur_radius, background_radius);
	return advanced_options;
}
