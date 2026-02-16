package main

import (
	"flag"
	"fmt"
	"image"
	"os"
	"path/filepath"
	"strings"

	"gocv.io/x/gocv"
)

func main() {
	output := flag.String("o", "screenshot.png", "output image path (.ppm, .png, .jpg, .jpeg)")
	list := flag.Bool("list", false, "list available cameras and exit")
	flag.Parse()

	if *list {
		cameras, rc := ListCameras()
		if rc != 0 {
			fmt.Fprintf(os.Stderr, "list cameras failed: %d\n", rc)
			os.Exit(1)
		}
		if len(cameras) == 0 {
			fmt.Println("No cameras found")
			return
		}
		for _, camera := range cameras {
			fmt.Println(camera)
		}
		return
	}

	outputPath, err := filepath.Abs(*output)
	if err != nil {
		fmt.Fprintln(os.Stderr, "output path error:", err)
		os.Exit(1)
	}

	handle := Open()
	if handle == nil {
		fmt.Fprintln(os.Stderr, "camera open failed")
		os.Exit(1)
	}
	defer Close(handle)

	if rc := Start(handle); rc != 0 {
		fmt.Fprintf(os.Stderr, "camera start failed: %d\n", rc)
		os.Exit(1)
	}

	width := FrameWidth(handle)
	height := FrameHeight(handle)
	if width <= 0 || height <= 0 {
		fmt.Fprintf(os.Stderr, "invalid frame size: %dx%d\n", width, height)
		os.Exit(1)
	}

	rgb, rc := CaptureFrame(handle, width, height)
	if rc < 0 {
		fmt.Fprintf(os.Stderr, "capture failed: %d\n", rc)
		os.Exit(1)
	}

	src, err := gocv.NewMatFromBytes(height, width, gocv.MatTypeCV8UC3, rgb)
	if err != nil {
		fmt.Fprintln(os.Stderr, "mat creation failed:", err)
		os.Exit(1)
	}
	defer src.Close()

	resized := gocv.NewMat()
	defer resized.Close()
	gocv.Resize(src, &resized, image.Pt(640, 480), 0, 0, gocv.InterpolationLinear)

	bgr := gocv.NewMat()
	defer bgr.Close()
	gocv.CvtColor(resized, &bgr, gocv.ColorRGBToBGR)

	ext := strings.ToLower(filepath.Ext(outputPath))
	if ext != ".png" && ext != ".jpg" && ext != ".jpeg" {
		fmt.Fprintln(os.Stderr, "unsupported output extension; use .png/.jpg/.jpeg")
		os.Exit(1)
	}

	if ok := gocv.IMWrite(outputPath, bgr); !ok {
		fmt.Fprintln(os.Stderr, "failed to write image")
		os.Exit(1)
	}

	fmt.Println("Saved screenshot:", outputPath)
}
