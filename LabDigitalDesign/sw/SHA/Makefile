all: master master_driver

master: master.cpp OverlayControl.c OverlayControl.h
	g++ -O3 -Wall -I /usr/include master.cpp OverlayControl.c -o master -lm -lcma -lpthread

master_driver: master_driver.cpp OverlayControl.c OverlayControl.h
	g++ -O3 -Wall -I /usr/include master_driver.cpp OverlayControl.c -o master_driver -lm -lcma -lpthread

clean:
	rm -f master master_driver

