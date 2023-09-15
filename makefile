AS 	= nasm
ASFLAGS = -f elf64 -w+all -w+error
LD      = ld
LDFLAGS = --fatal-warnings
SOURCES = scopy.asm
OBJECTS = scopy.o
EXECUTABLE = scopy

all: $(SOURCES) $(EXECUTABLE)

$(EXECUTABLE): $(OBJECTS)
	$(LD) $(LDFLAGS) $(OBJECTS) -o $@

$(OBJECTS): $(SOURCES)
	$(AS) $(ASFLAGS) -g $(SOURCES)

clean:
	rm -rf *.o $(EXECUTABLE)
